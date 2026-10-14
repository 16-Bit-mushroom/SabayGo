"""Fleet and crew management: the member roster (brief 8).

Three lists: operators (van owners, who always drive; no login), vans
(one per operator) and Dispatchers. Each record is Pending until the
Terminal Manager validates it, and only a validated record may later be
assigned to a trip (step 4). Import and export live in roster.py.

Scope, per the consultation: MONITORING ONLY. There is deliberately no
maintenance scheduling, service history, parts, or cost tracking.
`operational_status` is a flag that keeps an out-of-service van from
being dispatched -- it is not a maintenance module.
"""

from __future__ import annotations

import datetime as dt
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import or_, select

from app.api.v1.deps import MANAGER, OFFICE, CurrentUser, SessionDep
from app.core.db import commit_or_conflict
from app.core.exceptions import (
    ConflictError,
    InvalidInputError,
    NotFoundError,
    PermissionDeniedError,
)
from app.core.images import sniff_image_ext
from app.core.security import hash_password
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.domain.value_objects import (
    CpcReference,
    LicenseNumber,
    PhoneNumber,
    PlateNumber,
)
from app.infrastructure.models import (
    DataTransfer,
    Operator,
    Route,
    StaffProfile,
    User,
    Van,
)

router = APIRouter(prefix="/fleet", tags=["fleet"])

STAFF_ROLES = (Role.DISPATCHER.value, Role.CASHIER.value, Role.TERMINAL_MANAGER.value)

VAN_PHOTO_DIR = Path(__file__).resolve().parents[3] / "media" / "vans"
PHOTO_SIDES = ("front", "rear", "left", "right")
MAX_PHOTO_BYTES = 5 * 1024 * 1024


def _now() -> dt.datetime:
    return dt.datetime.now(APP_TZ).replace(tzinfo=None)


def _optional(cls, value: str | None):
    """Run a value object over an optional field; blank means absent."""
    return cls(value).value if value and value.strip() else None


# ===================================================================
# Validation (brief 3 and 8)
# ===================================================================
class ValidationIn(BaseModel):
    validation_status: str = Field(pattern="^(pending|validated|rejected|suspended)$")


async def _decide(session, record, status: str, user: User) -> None:
    """Record the Terminal Manager's decision on a roster record.

    Separation of duties (brief 3): whoever imported a record is not the
    only one who approves it, so they cannot validate it themselves. The
    import is open to the Cashier; the validation is not.
    """
    if status == "validated" and record.import_batch_id:
        batch = await session.get(DataTransfer, record.import_batch_id)
        if batch is not None and batch.performed_by == user.user_id:
            raise PermissionDeniedError(
                "You imported this record, so someone else must validate it."
            )
    record.validation_status = status
    if status == "pending":
        record.validated_by = record.validated_at = None
    else:
        record.validated_by = user.user_id
        record.validated_at = _now()


def _reopen(record) -> None:
    """A changed record is no longer the record that was validated."""
    if record.validation_status == "validated":
        record.validation_status = "pending"
        record.validated_by = record.validated_at = None


def _apply(record, changes: dict) -> bool:
    """Write the fields that differ; True if any did."""
    changed = False
    for field, value in changes.items():
        if getattr(record, field) != value:
            setattr(record, field, value)
            changed = True
    return changed


# ===================================================================
# Operators
# ===================================================================
class OperatorFields(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=255)
    contact_number: str | None = None
    email: EmailStr | None = None
    payout_ref: str | None = Field(default=None, max_length=64)
    license_number: str | None = None
    license_expiry: dt.date | None = None

    @field_validator("full_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        return v.strip() if v else v

    @field_validator("contact_number")
    @classmethod
    def _contact(cls, v: str | None) -> str | None:
        return PhoneNumber(v).normalized() if v else v

    @field_validator("email")
    @classmethod
    def _email(cls, v: str | None) -> str | None:
        return v.lower() if v else v

    @field_validator("license_number")
    @classmethod
    def _licence(cls, v: str | None) -> str | None:
        return LicenseNumber(v).value if v else v


class OperatorIn(OperatorFields):
    full_name: str = Field(min_length=2, max_length=255)
    contact_number: str
    license_number: str
    license_expiry: dt.date


class OperatorPatch(OperatorFields):
    membership_status: str | None = Field(
        default=None, pattern="^(active|suspended|inactive)$"
    )


class OperatorOut(BaseModel):
    operator_id: str
    full_name: str
    contact_number: str
    email: str | None
    payout_ref: str | None
    license_number: str
    license_expiry: dt.date
    license_expired: bool
    membership_status: str
    validation_status: str
    validated_by: str | None
    validated_at: dt.datetime | None
    import_batch_id: str | None
    van_id: str | None
    plate_number: str | None


def _operator_out(op: Operator, van: Van | None) -> OperatorOut:
    fields = {c: getattr(op, c) for c in OperatorOut.model_fields
              if hasattr(Operator, c)}
    return OperatorOut(
        **fields,
        license_expired=op.license_expiry < dt.datetime.now(APP_TZ).date(),
        van_id=van.van_id if van else None,
        plate_number=van.plate_number if van else None,
    )


async def _operator_clash(
    session, contact: str | None, licence: str | None, exclude: str | None = None
) -> None:
    conds = []
    if contact:
        conds.append(Operator.contact_number == contact)
    if licence:
        conds.append(Operator.license_number == licence)
    if not conds:
        return
    stmt = select(Operator).where(or_(*conds))
    if exclude:
        stmt = stmt.where(Operator.operator_id != exclude)
    if (await session.execute(stmt.limit(1))).scalar_one_or_none() is not None:
        raise ConflictError(
            "An operator with that contact number or licence is already on the roster."
        )


async def _operator_with_van(session, operator_id: str) -> tuple[Operator, Van | None]:
    op = await session.get(Operator, operator_id)
    if op is None:
        raise NotFoundError("Operator not found.")
    van = (await session.execute(
        select(Van).where(Van.operator_id == operator_id)
    )).scalar_one_or_none()
    return op, van


@router.get("/operators", response_model=list[OperatorOut],
            dependencies=[Depends(OFFICE)])
async def list_operators(
    session: SessionDep, validation_status: str | None = None
) -> list[OperatorOut]:
    stmt = (
        select(Operator, Van)
        .outerjoin(Van, Van.operator_id == Operator.operator_id)
        .order_by(Operator.full_name)
    )
    if validation_status:
        stmt = stmt.where(Operator.validation_status == validation_status)
    return [_operator_out(op, van) for op, van in (await session.execute(stmt)).all()]


@router.post("/operators", response_model=OperatorOut, status_code=201,
             dependencies=[Depends(MANAGER)])
async def create_operator(payload: OperatorIn, session: SessionDep) -> OperatorOut:
    """Add a van owner to the roster. Pending until validated."""
    await _operator_clash(session, payload.contact_number, payload.license_number)
    now = _now()
    op = Operator(
        operator_id=str(uuid.uuid4()),
        **payload.model_dump(),
        membership_status="active",
        validation_status="pending",
        created_at=now,
        updated_at=now,
    )
    session.add(op)
    await commit_or_conflict(session, "That operator is already on the roster.")
    return _operator_out(op, None)


@router.patch("/operators/{operator_id}", response_model=OperatorOut,
              dependencies=[Depends(MANAGER)])
async def update_operator(
    operator_id: str, payload: OperatorPatch, session: SessionDep
) -> OperatorOut:
    """Correct or renew a record. A validated record goes back to
    Pending: the Terminal Manager validates what is on file now."""
    op, van = await _operator_with_van(session, operator_id)
    changes = payload.model_dump(exclude_unset=True)
    for required in ("full_name", "contact_number", "license_number", "license_expiry"):
        if required in changes and changes[required] is None:
            raise InvalidInputError(f"{required} cannot be removed.")
    await _operator_clash(
        session, changes.get("contact_number"), changes.get("license_number"),
        exclude=operator_id,
    )
    status = changes.pop("membership_status", None)
    if _apply(op, changes):
        _reopen(op)
    if status:
        op.membership_status = status
    op.updated_at = _now()
    await commit_or_conflict(session, "That operator is already on the roster.")
    return _operator_out(op, van)


@router.patch("/operators/{operator_id}/validation", response_model=OperatorOut,
              dependencies=[Depends(MANAGER)])
async def validate_operator(
    operator_id: str, payload: ValidationIn, session: SessionDep, user: CurrentUser
) -> OperatorOut:
    op, van = await _operator_with_van(session, operator_id)
    await _decide(session, op, payload.validation_status, user)
    await session.commit()
    return _operator_out(op, van)


# ===================================================================
# Vans
# ===================================================================
class VanFields(BaseModel):
    plate_number: str | None = None
    operator_id: str | None = None
    brand: str | None = Field(default=None, max_length=64)
    model: str | None = Field(default=None, max_length=64)
    color: str | None = Field(default=None, max_length=32)
    # LTFRB-regulated ceiling; the DB CHECK enforces it too.
    seat_capacity: int | None = Field(default=None, ge=1, le=14)
    cpc_case_no: str | None = None
    cpc_number: str | None = None
    registered_route_id: str | None = None
    has_cabin_camera: bool | None = None
    camera_device_id: str | None = None

    @field_validator("plate_number")
    @classmethod
    def _plate(cls, v: str | None) -> str | None:
        return PlateNumber(v).value if v else v

    @field_validator("cpc_case_no", "cpc_number")
    @classmethod
    def _cpc(cls, v: str | None) -> str | None:
        return _optional(CpcReference, v)

    @field_validator("camera_device_id")
    @classmethod
    def _camera(cls, v: str | None) -> str | None:
        return v or None


class VanIn(VanFields):
    plate_number: str
    # One van per operator (brief 3): the van is created with its owner.
    operator_id: str
    seat_capacity: int = Field(default=14, ge=1, le=14)
    has_cabin_camera: bool = False


class VanOut(BaseModel):
    van_id: str
    plate_number: str
    operator_id: str
    operator_name: str
    brand: str | None
    model: str | None
    color: str | None
    seat_capacity: int
    operational_status: str
    registered_route_id: str | None
    has_cabin_camera: bool
    camera_device_id: str | None
    cpc_case_no: str | None
    cpc_number: str | None
    camera_installed_at: dt.date | None
    photo_front_url: str | None
    photo_rear_url: str | None
    photo_left_url: str | None
    photo_right_url: str | None
    validation_status: str
    validated_by: str | None
    validated_at: dt.datetime | None
    import_batch_id: str | None


class VanStatusIn(BaseModel):
    operational_status: str = Field(pattern="^(active|maintenance|inactive)$")


def _van_out(van: Van, op: Operator) -> VanOut:
    fields = {c: getattr(van, c) for c in VanOut.model_fields if hasattr(Van, c)}
    return VanOut(**fields, operator_name=op.full_name)


async def _van_with_operator(session, van_id: str) -> tuple[Van, Operator]:
    van = await session.get(Van, van_id)
    if van is None:
        raise NotFoundError("Van not found.")
    return van, await session.get(Operator, van.operator_id)


async def _check_van_refs(
    session, changes: dict, exclude: str | None = None
) -> Operator | None:
    """Plate unique; route exists; operator exists and has no other van."""
    plate, operator_id = changes.get("plate_number"), changes.get("operator_id")
    route_id = changes.get("registered_route_id")
    if route_id and await session.get(Route, route_id) is None:
        raise NotFoundError("Route not found.")
    if plate:
        stmt = select(Van.van_id).where(Van.plate_number == plate)
        if exclude:
            stmt = stmt.where(Van.van_id != exclude)
        if (await session.execute(stmt)).first() is not None:
            raise ConflictError(f"A van with plate {plate} already exists.")
    if not operator_id:
        return None
    op = await session.get(Operator, operator_id)
    if op is None:
        raise NotFoundError("Operator not found. Add the operator first.")
    stmt = select(Van.plate_number).where(Van.operator_id == operator_id)
    if exclude:
        stmt = stmt.where(Van.van_id != exclude)
    other = (await session.execute(stmt)).scalar_one_or_none()
    if other is not None:
        raise ConflictError(
            f"{op.full_name} already has van {other}: one van per operator."
        )
    return op


@router.get("/vans", response_model=list[VanOut], dependencies=[Depends(OFFICE)])
async def list_vans(
    session: SessionDep,
    status: str | None = None,
    validation_status: str | None = None,
) -> list[VanOut]:
    stmt = (
        select(Van, Operator)
        .join(Operator, Operator.operator_id == Van.operator_id)
        .order_by(Van.plate_number)
    )
    if status:
        stmt = stmt.where(Van.operational_status == status)
    if validation_status:
        stmt = stmt.where(Van.validation_status == validation_status)
    return [_van_out(v, op) for v, op in (await session.execute(stmt)).all()]


@router.post("/vans", response_model=VanOut, status_code=201,
             dependencies=[Depends(MANAGER)])
async def create_van(payload: VanIn, session: SessionDep) -> VanOut:
    op = await _check_van_refs(session, payload.model_dump())
    now = _now()
    van = Van(
        van_id=str(uuid.uuid4()),
        **payload.model_dump(),
        operational_status="active",
        validation_status="pending",
        created_at=now,
        updated_at=now,
    )
    session.add(van)
    await commit_or_conflict(
        session, "That plate or operator is already on another van."
    )
    return _van_out(van, op)


@router.patch("/vans/{van_id}", response_model=VanOut,
              dependencies=[Depends(MANAGER)])
async def update_van(van_id: str, payload: VanFields, session: SessionDep) -> VanOut:
    """Correct a van record or hand it to another operator. A validated
    van goes back to Pending."""
    van, op = await _van_with_operator(session, van_id)
    changes = payload.model_dump(exclude_unset=True)
    for required in ("plate_number", "operator_id", "seat_capacity", "has_cabin_camera"):
        if required in changes and changes[required] is None:
            raise InvalidInputError(f"{required} cannot be removed.")
    new_op = await _check_van_refs(session, changes, exclude=van_id)
    if _apply(van, changes):
        _reopen(van)
    van.updated_at = _now()
    await commit_or_conflict(
        session, "That plate or operator is already on another van."
    )
    return _van_out(van, new_op or op)


@router.patch("/vans/{van_id}/status", dependencies=[Depends(MANAGER)])
async def set_van_status(
    van_id: str, payload: VanStatusIn, session: SessionDep
) -> dict:
    """Flag a van in or out of service.

    A van marked maintenance or inactive is not assigned by the trip
    generator. Existing trips keep their assignment -- reassigning a van
    mid-schedule is the Terminal Manager decision, not an automatic one.
    """
    van = await session.get(Van, van_id)
    if van is None:
        raise NotFoundError("Van not found.")
    van.operational_status = payload.operational_status
    van.updated_at = _now()
    await session.commit()
    return {
        "van_id": van_id,
        "plate_number": van.plate_number,
        "operational_status": van.operational_status,
    }


@router.put("/vans/{van_id}/photos/{side}", response_model=VanOut,
            dependencies=[Depends(OFFICE)])
async def upload_van_photo(
    van_id: str, side: str, session: SessionDep, image: UploadFile = File(...)
) -> VanOut:
    """One of the van's four photographs (brief 8): not part of an
    import, uploaded afterwards by whoever imported it. A new photo on a
    validated van returns it to Pending."""
    if side not in PHOTO_SIDES:
        raise NotFoundError(f"Photo side must be one of: {', '.join(PHOTO_SIDES)}.")
    van, op = await _van_with_operator(session, van_id)
    data = await image.read(MAX_PHOTO_BYTES + 1)
    if len(data) > MAX_PHOTO_BYTES:
        raise InvalidInputError("The photo is larger than 5 MB.")
    ext = sniff_image_ext(data)
    if ext is None:
        raise InvalidInputError("The photo must be a JPEG, PNG or WebP image.")

    VAN_PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    name = f"{van_id}-{side}-{uuid.uuid4().hex[:8]}.{ext}"
    (VAN_PHOTO_DIR / name).write_bytes(data)
    column = f"photo_{side}_url"
    old = getattr(van, column)
    setattr(van, column, f"/media/vans/{name}")
    _reopen(van)
    van.updated_at = _now()
    await session.commit()

    if old and old.startswith("/media/vans/"):
        (VAN_PHOTO_DIR / Path(old).name).unlink(missing_ok=True)
    return _van_out(van, op)


@router.patch("/vans/{van_id}/validation", response_model=VanOut,
              dependencies=[Depends(MANAGER)])
async def validate_van(
    van_id: str, payload: ValidationIn, session: SessionDep, user: CurrentUser
) -> VanOut:
    van, op = await _van_with_operator(session, van_id)
    if payload.validation_status == "validated":
        missing = [s for s in PHOTO_SIDES if not getattr(van, f"photo_{s}_url")]
        if missing:
            raise ConflictError(
                f"Upload the {', '.join(missing)} photo(s) before validating this van."
            )
    await _decide(session, van, payload.validation_status, user)
    await session.commit()
    return _van_out(van, op)


# ===================================================================
# Crew
# ===================================================================
class StaffIn(BaseModel):
    email: EmailStr
    phone_number: str
    password: str = Field(min_length=8)
    role: str = Field(pattern="^(dispatcher|cashier|terminal_manager)$")
    first_name: str
    last_name: str
    middle_name: str | None = None
    assigned_terminal_id: str | None = None
    cooperative_name: str | None = None


class StaffOut(BaseModel):
    user_id: str
    email: str
    phone_number: str | None
    role: str
    first_name: str
    middle_name: str | None
    last_name: str
    employment_status: str
    cooperative_name: str | None
    assigned_terminal_id: str | None
    # Read for Dispatchers only: the office staff are not on the roster.
    validation_status: str
    validated_at: dt.datetime | None


def _staff_out(user: User, profile: StaffProfile) -> StaffOut:
    return StaffOut(
        user_id=user.user_id,
        email=user.email,
        phone_number=user.phone_number,
        role=user.role,
        first_name=profile.first_name,
        middle_name=profile.middle_name,
        last_name=profile.last_name,
        employment_status=profile.employment_status,
        cooperative_name=profile.cooperative_name,
        assigned_terminal_id=profile.assigned_terminal_id,
        validation_status=profile.validation_status,
        validated_at=profile.validated_at,
    )


@router.get("/crew", response_model=list[StaffOut], dependencies=[Depends(OFFICE)])
async def list_crew(session: SessionDep, role: str | None = None) -> list[StaffOut]:
    stmt = (
        select(User, StaffProfile)
        .join(StaffProfile, StaffProfile.user_id == User.user_id)
        .where(User.role.in_(STAFF_ROLES))
        .order_by(StaffProfile.last_name)
    )
    if role:
        stmt = stmt.where(User.role == role)
    result = await session.execute(stmt)
    return [_staff_out(user, profile) for user, profile in result.all()]


@router.post("/crew", response_model=StaffOut, status_code=201,
             dependencies=[Depends(MANAGER)])
async def create_staff(payload: StaffIn, session: SessionDep) -> StaffOut:
    """Provision a Dispatcher, Cashier or Terminal Manager account.

    Staff are NOT self-registering -- employment is A2Z's decision, so only
    the Terminal Manager creates these. /auth/register is passengers only.
    One login per person: StartedBy, AssignedBy and ChangedBy must name
    someone, so a shared office account is not offered.
    The operator (van owner) has no account -- a roster record instead.
    A new Dispatcher is Pending on the roster until validated.
    """
    phone = PhoneNumber(payload.phone_number).normalized()
    email = payload.email.lower()

    clash = await session.execute(
        select(User).where(or_(User.email == email, User.phone_number == phone))
    )
    if clash.scalar_one_or_none() is not None:
        raise ConflictError("That email address or phone number is already in use.")

    now = _now()
    user = User(
        user_id=str(uuid.uuid4()),
        email=email,
        phone_number=phone,
        password_hash=hash_password(payload.password),
        role=payload.role,
        account_status="active",
        created_at=now,
        updated_at=now,
    )
    session.add(user)
    await session.flush()

    profile = StaffProfile(
        user_id=user.user_id,
        first_name=payload.first_name.strip(),
        middle_name=payload.middle_name,
        last_name=payload.last_name.strip(),
        cooperative_name=payload.cooperative_name,
        assigned_terminal_id=payload.assigned_terminal_id,
        employment_status="active",
        validation_status="pending",
    )
    session.add(profile)
    await commit_or_conflict(
        session, "That email address or phone number is already in use."
    )
    return _staff_out(user, profile)


@router.patch("/crew/{user_id}/status", dependencies=[Depends(MANAGER)])
async def set_staff_status(
    user_id: str, status: str, session: SessionDep
) -> dict:
    """Suspend or reinstate a crew member.

    Deactivating rather than deleting: a Dispatcher who leaves still appears
    on historic manifests, and those records must not break.
    """
    if status not in ("active", "suspended", "inactive"):
        raise ConflictError("Status must be active, suspended, or inactive.")

    user = await session.get(User, user_id)
    profile = await session.get(StaffProfile, user_id)
    if user is None or profile is None or user.role not in STAFF_ROLES:
        raise NotFoundError("Crew member not found.")

    user.account_status = status
    profile.employment_status = status
    user.updated_at = _now()
    await session.commit()
    return {"user_id": user_id, "status": status}


@router.patch("/crew/{user_id}/validation", response_model=StaffOut,
              dependencies=[Depends(MANAGER)])
async def validate_dispatcher(
    user_id: str, payload: ValidationIn, session: SessionDep, user: CurrentUser
) -> StaffOut:
    """Validate a Dispatcher's roster record. Office staff are not on the
    roster, so this refuses them."""
    staff = await session.get(User, user_id)
    profile = await session.get(StaffProfile, user_id)
    if staff is None or profile is None or staff.role not in STAFF_ROLES:
        raise NotFoundError("Crew member not found.")
    if staff.role != Role.DISPATCHER.value:
        raise ConflictError("Only Dispatchers are validated on the roster.")
    await _decide(session, profile, payload.validation_status, user)
    await session.commit()
    return _staff_out(staff, profile)
