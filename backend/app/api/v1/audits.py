"""YOLOv8 audit and revenue reconciliation endpoints."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import text

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.audit.trigger_audit import (
    AuditQueueUseCase,
    ResolveAuditUseCase,
    TriggerAuditUseCase,
)
from app.domain.enums import Role
from app.infrastructure.clients.ai_node_client import AiNodeClient

router = APIRouter(tags=["audit"])

OPERATOR = require_roles(Role.OPERATOR, Role.ADMIN)
CREW = require_roles(Role.CONDUCTOR, Role.DRIVER, Role.OPERATOR, Role.ADMIN)


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


@router.post("/audits/{audit_id}/resolve", dependencies=[Depends(OPERATOR)])
async def resolve_audit(
    audit_id: str, payload: ResolveRequest, session: SessionDep, user: CurrentUser
) -> dict:
    return await ResolveAuditUseCase(session).execute(
        audit_id=audit_id,
        resolution=payload.resolution,
        notes=payload.notes,
        resolved_by_user_id=user.user_id,
    )


@router.get("/audits/pending", dependencies=[Depends(OPERATOR)])
async def pending_audits(session: SessionDep, limit: int = Query(50, le=200)) -> list:
    """Unresolved variances -- the operator console's audit queue."""
    return await AuditQueueUseCase(session).pending(limit=limit)


@router.get("/audits/node-health", dependencies=[Depends(CREW)])
async def node_health() -> dict:
    """Is the van's camera node reachable? Check before relying on a demo."""
    return await AiNodeClient().health()


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
    dependencies=[Depends(OPERATOR)],
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


@router.get("/revenue/summary", dependencies=[Depends(OPERATOR)], tags=["revenue"])
async def revenue_summary(
    session: SessionDep,
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
) -> dict:
    """Headline figures for the operator dashboard."""
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
