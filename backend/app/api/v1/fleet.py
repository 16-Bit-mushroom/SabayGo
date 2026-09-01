"""Fleet and crew management.

Scope, per the consultation: driver, van, route and schedule, MONITORING
ONLY. There is deliberately no maintenance scheduling, service history,
parts, or cost tracking. `operational_status` is a flag that keeps an
out-of-service van from being dispatched -- it is not a maintenance module.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import or_, select

from app.api.v1.deps import SessionDep, require_roles
from app.core.exceptions import ConflictError, NotFoundError
from app.core.security import hash_password
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.domain.value_objects import LicenseNumber, PhoneNumber
from app.infrastructure.models import (
    DriverCredential,
    StaffProfile,
    User,
    Van,
)

router = APIRouter(prefix="/fleet", tags=["fleet"])
OPERATOR = require_roles(Role.OPERATOR, Role.ADMIN)


# ===================================================================
# Vans
# ===================================================================
class VanIn(BaseModel):
    plate_number: str = Field(min_length=3, max_length=20)
    brand: str | None = None
    model: str | None = None
    color: str | None = None
    # LTFRB-regulated ceiling; the DB CHECK enforces it too.
    seat_capacity: int = Field(default=14, ge=1, le=14)
    cpc_case_no: str | None = None
    cpc_number: str | None = None
    registered_route_id: str | None = None
    has_cabin_camera: bool = False
    camera_device_id: str | None = None


class VanOut(BaseModel):
    van_id: str
    plate_number: str
    brand: str | None
    model: str | None
    color: str | None
    seat_capacity: int
    operational_status: str
    registered_route_id: str | None
    has_cabin_camera: bool
    camera_device_id: str | None


class VanStatusIn(BaseModel):
    operational_status: str = Field(pattern="^(active|maintenance|inactive)$")


@router.get("/vans", response_model=list[VanOut], dependencies=[Depends(OPERATOR)])
async def list_vans(session: SessionDep, status: str | None = None) -> list[VanOut]:
    stmt = select(Van).order_by(Van.plate_number)
    if status:
        stmt = stmt.where(Van.operational_status == status)
    result = await session.execute(stmt)
    return [VanOut(**{c: getattr(v, c) for c in VanOut.model_fields})
            for v in result.scalars()]


@router.post("/vans", response_model=VanOut, status_code=201,
             dependencies=[Depends(OPERATOR)])
async def create_van(payload: VanIn, session: SessionDep) -> VanOut:
    plate = payload.plate_number.upper().strip()
    existing = await session.execute(select(Van).where(Van.plate_number == plate))
    if existing.scalar_one_or_none() is not None:
        raise ConflictError(f"A van with plate {plate} already exists.")

    now = dt.datetime.now(APP_TZ)
    van = Van(
        van_id=str(uuid.uuid4()),
        plate_number=plate,
        brand=payload.brand,
        model=payload.model,
        color=payload.color,
        seat_capacity=payload.seat_capacity,
        operational_status="active",
        registered_route_id=payload.registered_route_id,
        cpc_case_no=payload.cpc_case_no,
        cpc_number=payload.cpc_number,
        has_cabin_camera=payload.has_cabin_camera,
        camera_device_id=payload.camera_device_id or None,
        created_at=now,
        updated_at=now,
    )
    session.add(van)
    await session.commit()
    return VanOut(**{c: getattr(van, c) for c in VanOut.model_fields})


@router.patch("/vans/{van_id}/status", dependencies=[Depends(OPERATOR)])
async def set_van_status(
    van_id: str, payload: VanStatusIn, session: SessionDep
) -> dict:
    """Flag a van in or out of service.

    A van marked maintenance or inactive is not assigned by the trip
    generator. Existing trips keep their assignment -- reassigning a van
    mid-schedule is an operator decision, not an automatic one.
    """
    van = await session.get(Van, van_id)
    if van is None:
        raise NotFoundError("Van not found.")
    van.operational_status = payload.operational_status
    van.updated_at = dt.datetime.now(APP_TZ)
    await session.commit()
    return {
        "van_id": van_id,
        "plate_number": van.plate_number,
        "operational_status": van.operational_status,
    }


# ===================================================================
# Crew
# ===================================================================
class StaffIn(BaseModel):
    email: EmailStr
    phone_number: str
    password: str = Field(min_length=8)
    role: str = Field(pattern="^(conductor|driver|operator)$")
    first_name: str
    last_name: str
    middle_name: str | None = None
    assigned_terminal_id: str | None = None
    cooperative_name: str | None = None
    # Required when role is driver.
    license_number: str | None = None
    license_expiry_date: dt.date | None = None
    cttmo_id_number: str | None = None


class StaffOut(BaseModel):
    user_id: str
    email: str
    role: str
    first_name: str
    last_name: str
    employment_status: str
    assigned_terminal_id: str | None
    license_number: str | None = None


@router.get("/crew", response_model=list[StaffOut], dependencies=[Depends(OPERATOR)])
async def list_crew(session: SessionDep, role: str | None = None) -> list[StaffOut]:
    stmt = (
        select(User, StaffProfile)
        .join(StaffProfile, StaffProfile.user_id == User.user_id)
        .order_by(StaffProfile.last_name)
    )
    if role:
        stmt = stmt.where(User.role == role)
    result = await session.execute(stmt)

    out: list[StaffOut] = []
    for user, profile in result.all():
        credential = await session.get(DriverCredential, user.user_id)
        out.append(
            StaffOut(
                user_id=user.user_id,
                email=user.email,
                role=user.role,
                first_name=profile.first_name,
                last_name=profile.last_name,
                employment_status=profile.employment_status,
                assigned_terminal_id=profile.assigned_terminal_id,
                license_number=credential.license_number if credential else None,
            )
        )
    return out


@router.post("/crew", response_model=StaffOut, status_code=201,
             dependencies=[Depends(OPERATOR)])
async def create_staff(payload: StaffIn, session: SessionDep) -> StaffOut:
    """Provision a conductor, driver, or operator account.

    Staff are NOT self-registering -- employment is a cooperative decision,
    so only an operator can create these. /auth/register is passengers only.
    """
    phone = PhoneNumber(payload.phone_number).normalized()
    email = payload.email.lower()

    clash = await session.execute(
        select(User).where(or_(User.email == email, User.phone_number == phone))
    )
    if clash.scalar_one_or_none() is not None:
        raise ConflictError("That email address or phone number is already in use.")

    if payload.role == Role.DRIVER.value:
        if not payload.license_number or not payload.license_expiry_date:
            raise ConflictError(
                "A driver requires a licence number and expiry date."
            )
        licence = LicenseNumber(payload.license_number)
        if payload.license_expiry_date <= dt.date.today():
            raise ConflictError("That licence has already expired.")
    else:
        licence = None

    now = dt.datetime.now(APP_TZ)
    user_id = str(uuid.uuid4())

    session.add(
        User(
            user_id=user_id,
            email=email,
            phone_number=phone,
            password_hash=hash_password(payload.password),
            role=payload.role,
            account_status="active",
            created_at=now,
            updated_at=now,
        )
    )
    await session.flush()

    session.add(
        StaffProfile(
            user_id=user_id,
            first_name=payload.first_name.strip(),
            middle_name=payload.middle_name,
            last_name=payload.last_name.strip(),
            cooperative_name=payload.cooperative_name,
            assigned_terminal_id=payload.assigned_terminal_id,
            employment_status="active",
        )
    )

    if licence is not None:
        session.add(
            DriverCredential(
                user_id=user_id,
                license_number=licence.value,
                license_expiry_date=payload.license_expiry_date,
                cttmo_id_number=payload.cttmo_id_number,
            )
        )

    await session.commit()
    return StaffOut(
        user_id=user_id,
        email=email,
        role=payload.role,
        first_name=payload.first_name,
        last_name=payload.last_name,
        employment_status="active",
        assigned_terminal_id=payload.assigned_terminal_id,
        license_number=licence.value if licence else None,
    )


@router.patch("/crew/{user_id}/status", dependencies=[Depends(OPERATOR)])
async def set_staff_status(
    user_id: str, status: str, session: SessionDep
) -> dict:
    """Suspend or reinstate a crew member.

    Deactivating rather than deleting: a driver who leaves still appears on
    historic manifests and headcounts, and those records must not break.
    """
    if status not in ("active", "suspended", "inactive"):
        raise ConflictError("Status must be active, suspended, or inactive.")

    user = await session.get(User, user_id)
    profile = await session.get(StaffProfile, user_id)
    if user is None or profile is None:
        raise NotFoundError("Crew member not found.")

    user.account_status = status
    profile.employment_status = status
    user.updated_at = dt.datetime.now(APP_TZ)
    await session.commit()
    return {"user_id": user_id, "status": status}
