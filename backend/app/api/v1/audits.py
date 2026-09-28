"""YOLOv8 audit and revenue reconciliation endpoints."""

from __future__ import annotations

import csv
import datetime as dt
import io
from decimal import Decimal

from fastapi import APIRouter, Depends, File, Header, Query, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import text

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.core import timezone as app_tz
from app.core.exceptions import AuthenticationError, ConflictError
from app.application.audit import phone_capture_queue
from app.application.audit.trigger_audit import (
    AuditQueueUseCase,
    ResolveAuditUseCase,
    TriggerAuditUseCase,
)
from app.config import settings
from app.domain.enums import Role
from app.infrastructure.clients.ai_node_client import AiNodeClient

router = APIRouter(tags=["audit"])

COOP_ADMIN = require_roles(Role.COOP_ADMIN, Role.ADMIN)
CREW = require_roles(Role.CONDUCTOR, Role.DRIVER, Role.COOP_ADMIN, Role.ADMIN)


def verify_phone_device(x_device_key: str | None = Header(default=None)) -> None:
    """Authenticate the phone-as-camera PoC the same way the AI node and
    tracking units are authenticated -- a device cannot hold a user
    session. Retires with ai_capture_app once the Orange Pi is in hand."""
    if not settings.phone_capture_api_key:
        return  # unset in development; the endpoint stays open
    if x_device_key != settings.phone_capture_api_key:
        raise AuthenticationError("Invalid device key.")


class TriggerAuditRequest(BaseModel):
    trip_id: str
    leg_sequence: int = Field(ge=1)
    trigger_type: str = Field(default="manual")


class AuditResponse(BaseModel):
    audit_id: str
    trip_id: str
    leg_sequence: int
    visual_count: int
    booked_count: int
    variance: int
    resolution_status: str
    snapshot_url: str | None
    model_version: str
    inference_ms: int
    confidence_avg: float | None
    alert_raised: bool
    message: str


@router.post("/audits/trigger", response_model=AuditResponse,
             dependencies=[Depends(CREW)])
async def trigger_audit(
    payload: TriggerAuditRequest, session: SessionDep, user: CurrentUser
) -> AuditResponse:
    """Capture a cabin headcount and reconcile it against the manifest.

    Returns 502 if the AI node is unreachable. It never substitutes a
    fabricated count -- a missing audit is recoverable, a fake one that
    flags a driver for theft is not.
    """
    result = await TriggerAuditUseCase(session).execute(
        trip_id=payload.trip_id,
        leg_sequence=payload.leg_sequence,
        triggered_by_user_id=user.user_id,
        trigger_type=payload.trigger_type,
    )
    return AuditResponse(**result.__dict__)


class ResolveRequest(BaseModel):
    resolution: str = Field(pattern="^(resolved|ignored)$")
    notes: str = Field(min_length=1, max_length=512)


@router.post("/audits/{audit_id}/resolve", dependencies=[Depends(COOP_ADMIN)])
async def resolve_audit(
    audit_id: str, payload: ResolveRequest, session: SessionDep, user: CurrentUser
) -> dict:
    return await ResolveAuditUseCase(session).execute(
        audit_id=audit_id,
        resolution=payload.resolution,
        notes=payload.notes,
        resolved_by_user_id=user.user_id,
    )


class AuditQueueOut(BaseModel):
    audit_id: str
    trip_id: str
    trip_label: str
    service_date: dt.date
    leg_sequence: int
    trigger_type: str
    visual_count: int
    booked_count: int
    variance: int
    snapshot_url: str | None
    # AuditQueueUseCase._list() hands this straight off SQLAlchemy as a
    # Decimal. Without a response_model, FastAPI's default JSON encoder
    # renders Decimal as a *string* -- harmless for a client that re-parses
    # loosely, but a hard TypeError for one that expects a JSON number
    # (the console's `as num?` cast). Declaring float here makes Pydantic
    # coerce it for every caller, the same way AuditResponse already does
    # for /audits/trigger.
    confidence_avg: float | None
    inference_ms: int | None
    model_version: str | None
    captured_at: dt.datetime
    resolution_status: str
    resolved_by: str | None
    resolved_at: dt.datetime | None
    resolution_notes: str | None


@router.get("/audits/pending", response_model=list[AuditQueueOut], dependencies=[Depends(COOP_ADMIN)])
async def pending_audits(session: SessionDep, limit: int = Query(50, le=200)) -> list:
    """Unresolved variances -- the cooperative administrator console's audit queue."""
    return await AuditQueueUseCase(session).pending(limit=limit)


@router.get("/audits/history", response_model=list[AuditQueueOut], dependencies=[Depends(COOP_ADMIN)])
async def audit_history(
    session: SessionDep,
    status: str | None = Query(None, description="reconciled | resolved | ignored | failed"),
    trip_id: str | None = None,
    limit: int = Query(100, le=500),
) -> list:
    """Audits that have left the queue, newest first, with who resolved them (G.2)."""
    return await AuditQueueUseCase(session).history(
        limit=limit, status=status, trip_id=trip_id
    )


@router.get("/audits/node-health", dependencies=[Depends(CREW)])
async def node_health() -> dict:
    """Is the van's camera node reachable? Check before relying on a demo."""
    return await AiNodeClient().health()


# ===================================================================
# Phone-as-camera PoC -- a stand-in for the Orange Pi before that
# hardware is in hand. The Pi accepts an inbound call because it is
# always-on van hardware; a phone can't be called into, so it polls a
# pending-request slot instead. Retire this block when the Pi arrives.
# ===================================================================
class TriggerPhoneRequest(BaseModel):
    trip_id: str
    leg_sequence: int = Field(ge=1)


@router.post("/audits/trigger-phone", dependencies=[Depends(CREW)])
async def trigger_phone_capture(payload: TriggerPhoneRequest, user: CurrentUser) -> dict:
    """Ask the demo phone to capture next time it polls. A later trigger
    overwrites one the phone hasn't fulfilled yet -- one phone, one slot."""
    req = await phone_capture_queue.set_pending(
        trip_id=payload.trip_id,
        leg_sequence=payload.leg_sequence,
        requested_by_user_id=user.user_id,
    )
    return {
        "status": "pending",
        "trip_id": req.trip_id,
        "leg_sequence": req.leg_sequence,
        "requested_at": req.requested_at,
    }


@router.get("/audits/phone/pending", dependencies=[Depends(verify_phone_device)])
async def phone_pending() -> dict:
    """Polled by ai_capture_app. Empty object when nothing is waiting."""
    req = await phone_capture_queue.peek_pending()
    if req is None:
        return {}
    return {
        "trip_id": req.trip_id,
        "leg_sequence": req.leg_sequence,
        "requested_at": req.requested_at,
    }


@router.post(
    "/audits/phone/fulfill",
    response_model=AuditResponse,
    dependencies=[Depends(verify_phone_device)],
)
async def phone_fulfill(session: SessionDep, image: UploadFile = File(...)) -> AuditResponse:
    """The demo phone's answer to a pending request: the photo it took,
    reconciled against the manifest exactly like a direct AI-node capture."""
    req = await phone_capture_queue.consume_pending()
    if req is None:
        raise ConflictError("No pending capture request for this device.")

    result = await TriggerAuditUseCase(session).execute_from_upload(
        trip_id=req.trip_id,
        leg_sequence=req.leg_sequence,
        triggered_by_user_id=req.requested_by_user_id,
        image_bytes=await image.read(),
    )
    return AuditResponse(**result.__dict__)


# ===================================================================
# Revenue
# ===================================================================
revenue_router = APIRouter(prefix="/revenue", tags=["revenue"])


class TripRevenueOut(BaseModel):
    trip_id: str
    service_date: dt.date
    departure_datetime: dt.datetime
    route_name: str
    plate_number: str | None
    seat_capacity: int
    total_bookings: int
    app_bookings: int
    walkin_bookings: int
    collected_fare: Decimal
    cash_in_hand: Decimal = 0
    expected_fare: Decimal
    unreconciled_amount: Decimal
    max_yolo_variance: int | None
    pending_audits: int


@router.get(
    "/revenue/trips",
    response_model=list[TripRevenueOut],
    dependencies=[Depends(COOP_ADMIN)],
    tags=["revenue"],
)
async def trip_revenue(
    session: SessionDep,
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
    limit: int = Query(100, le=500),
) -> list[TripRevenueOut]:
    """Per-trip reconciliation, served from v_trip_revenue_reconciliation.

    The view already joins bookings, payments and audits; querying it
    directly keeps a five-way join out of the application layer.
    """
    return await _trip_rows(session, date_from, date_to, limit)


async def _trip_rows(
    session, date_from: dt.date | None, date_to: dt.date | None, limit: int
) -> list[TripRevenueOut]:
    clauses, params = [], {"limit": limit}
    if date_from:
        clauses.append("service_date >= :date_from")
        params["date_from"] = date_from
    if date_to:
        clauses.append("service_date <= :date_to")
        params["date_to"] = date_to
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""

    result = await session.execute(
        text(
            f"""
            SELECT * FROM v_trip_revenue_reconciliation
            {where}
            ORDER BY departure_datetime DESC
            LIMIT :limit
            """
        ),
        params,
    )
    return [TripRevenueOut(**dict(row._mapping)) for row in result]


# G.1 -- the cooperative keeps its books in a spreadsheet, so the
# reconciliation must leave the system in one. Column order mirrors the
# on-screen table; headings are the office's words, not the view's.
_EXPORT_COLUMNS: list[tuple[str, str]] = [
    ("service_date", "Date"),
    ("departure_datetime", "Departure"),
    ("route_name", "Route"),
    ("plate_number", "Plate"),
    ("seat_capacity", "Capacity"),
    ("total_bookings", "Passengers"),
    ("app_bookings", "App"),
    ("walkin_bookings", "Walk-in"),
    ("expected_fare", "Expected (PHP)"),
    ("collected_fare", "Collected (PHP)"),
    ("cash_in_hand", "Cash in hand (PHP)"),
    ("unreconciled_amount", "Unreconciled (PHP)"),
    ("max_yolo_variance", "Max variance"),
    ("pending_audits", "Pending audits"),
    ("trip_id", "Trip ID"),
]


def _export_rows(trips: list[TripRevenueOut]) -> list[list]:
    out = []
    for t in trips:
        d = t.model_dump()
        out.append([d[key] for key, _ in _EXPORT_COLUMNS])
    return out


def _to_csv(trips: list[TripRevenueOut]) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow([label for _, label in _EXPORT_COLUMNS])
    for row in _export_rows(trips):
        w.writerow(["" if v is None else v for v in row])
    return buf.getvalue().encode("utf-8-sig")  # BOM so Excel reads UTF-8


def _to_xlsx(trips: list[TripRevenueOut], date_from, date_to) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = "Trip revenue"
    ws.append([label for _, label in _EXPORT_COLUMNS])
    for cell in ws[1]:
        cell.font = Font(bold=True)
    money_cols = {i + 1 for i, (k, _) in enumerate(_EXPORT_COLUMNS) if k.endswith(("fare", "amount", "in_hand"))}
    for row in _export_rows(trips):
        ws.append([float(v) if isinstance(v, Decimal) else v for v in row])
    for r in ws.iter_rows(min_row=2):
        for c in r:
            if c.column in money_cols:
                c.number_format = "#,##0.00"
            elif isinstance(c.value, dt.datetime):
                c.number_format = "yyyy-mm-dd hh:mm"
            elif isinstance(c.value, dt.date):
                c.number_format = "yyyy-mm-dd"
    for i, (_, label) in enumerate(_EXPORT_COLUMNS, start=1):
        ws.column_dimensions[get_column_letter(i)].width = max(12, len(label) + 2)
    ws.freeze_panes = "A2"

    # Totals row -- what the bookkeeper actually wants at the bottom.
    if trips:
        last = ws.max_row
        ws.append([])
        total_row = ["Total", "", "", "", ""]
        for i, (k, _) in enumerate(_EXPORT_COLUMNS[5:], start=6):
            col = get_column_letter(i)
            if k in ("total_bookings", "app_bookings", "walkin_bookings") or i in money_cols:
                total_row.append(f"=SUM({col}2:{col}{last})")
            else:
                total_row.append("")
        ws.append(total_row)
        for c in ws[ws.max_row]:
            c.font = Font(bold=True)
            if c.column in money_cols:
                c.number_format = "#,##0.00"

    meta = wb.create_sheet("About")
    meta.append(["Generated", app_tz.now().strftime("%Y-%m-%d %H:%M")])
    meta.append(["From", str(date_from or "(all)")])
    meta.append(["To", str(date_to or "(all)")])
    meta.append(["Source", "SabayGo v_trip_revenue_reconciliation"])
    meta.append([])
    meta.append(["Cash in hand", "Cash the crew has collected but not yet remitted. Money in a pocket, not money missing."])
    meta.append(["Unreconciled", "Expected fare minus everything accounted for. This is the number to chase."])

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


@router.get("/revenue/export", dependencies=[Depends(COOP_ADMIN)], tags=["revenue"])
async def revenue_export(
    session: SessionDep,
    format: str = Query("xlsx", pattern="^(csv|xlsx)$"),
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
) -> Response:
    """Per-trip reconciliation as a spreadsheet (G.1). `xlsx` by default;
    `csv` for anything that cannot open Excel."""
    trips = await _trip_rows(session, date_from, date_to, limit=5000)
    span = f"{date_from or 'all'}_to_{date_to or 'all'}"
    if format == "csv":
        return Response(
            content=_to_csv(trips),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": f'attachment; filename="sabaygo_revenue_{span}.csv"'},
        )
    return Response(
        content=_to_xlsx(trips, date_from, date_to),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="sabaygo_revenue_{span}.xlsx"'},
    )


@router.get("/revenue/summary", dependencies=[Depends(COOP_ADMIN)], tags=["revenue"])
async def revenue_summary(
    session: SessionDep,
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
) -> dict:
    """Headline figures for the cooperative administrator dashboard."""
    clauses, params = [], {}
    if date_from:
        clauses.append("service_date >= :date_from")
        params["date_from"] = date_from
    if date_to:
        clauses.append("service_date <= :date_to")
        params["date_to"] = date_to
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""

    result = await session.execute(
        text(
            f"""
            SELECT
                COUNT(*)                             AS trips,
                COALESCE(SUM(total_bookings), 0)     AS total_bookings,
                COALESCE(SUM(app_bookings), 0)       AS app_bookings,
                COALESCE(SUM(walkin_bookings), 0)    AS walkin_bookings,
                COALESCE(SUM(collected_fare), 0)     AS collected_fare,
                -- Cash the crew has taken but not yet handed over.
                -- Deliberately separate from unreconciled: it is money
                -- in a pocket, not money missing.
                COALESCE(SUM(cash_in_hand), 0)       AS cash_in_hand,
                COALESCE(SUM(expected_fare), 0)      AS expected_fare,
                COALESCE(SUM(unreconciled_amount),0) AS unreconciled_amount,
                COALESCE(SUM(pending_audits), 0)     AS pending_audits
            FROM v_trip_revenue_reconciliation
            {where}
            """
        ),
        params,
    )
    row = dict(result.one()._mapping)

    total = int(row["total_bookings"]) or 1
    row["walkin_share_pct"] = round(int(row["walkin_bookings"]) / total * 100, 1)
    return row
