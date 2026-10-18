"""FastAPI application entry point."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.v1 import (
    auth,
    bookings,
    devices,
    disputes,
    driving_flags,
    edge,
    messaging,
    notifications,
    config as config_router,
    fleet,
    home_pickups,
    operations,
    payments,
    roster,
    sos,
    special_trips,
    statements,
    tracking,
    trips,
    users,
)
from app.config import settings
from app.application.edge.evidence import alert_silent_phones
from app.application.edge.retention import purge_expired_evidence
from app.application.operations.guards import sweep_abandoned_holds
from app.core.db import SessionFactory, engine
from app.core.exceptions import DomainError
from app.core.periodic import PeriodicJob

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
log = logging.getLogger("sabaygo")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Verify the database is reachable at boot. Failing here is far better
    # than discovering it on the first request during a demo.
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    log.info("Database connection verified.")

    # Abandoned payment holds were only released when another booking
    # happened to try that exact space. Until then search showed it as
    # unavailable.
    jobs = [
        PeriodicJob("Hold sweep", 60, lambda: sweep_abandoned_holds(SessionFactory)),
        # The phone of a trip under way went silent: alert at once; the
        # Unaudited mark waits for its stored reports (brief 4.4).
        PeriodicJob("Phone silence", 60, lambda: alert_silent_phones(SessionFactory)),
        # Stills, GPS readings and chat images past their retention period
        # (brief 4.5); what is under review or dispute stays.
        PeriodicJob("Evidence retention", 3600, lambda: purge_expired_evidence(SessionFactory)),
    ]
    for job in jobs:
        job.start()

    yield

    for job in jobs:
        await job.stop()
    await engine.dispose()


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="Booking aggregator and fleet management for terminal-based UV Express.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(DomainError)
async def domain_error_handler(_: Request, exc: DomainError) -> JSONResponse:
    """Single place where domain failures become HTTP responses.

    This is what lets the domain layer raise meaningful errors without
    importing fastapi -- keeping entities unit-testable with no server.
    """
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.code, "detail": exc.message},
    )


@app.get("/health", tags=["system"])
async def health() -> dict[str, str]:
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    return {"status": "ok", "environment": settings.environment}


app.include_router(auth.router, prefix="/api/v1")
app.include_router(bookings.router, prefix="/api/v1")
app.include_router(trips.router, prefix="/api/v1")
app.include_router(payments.router, prefix="/api/v1")
app.include_router(operations.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(messaging.router, prefix="/api/v1")
app.include_router(fleet.router, prefix="/api/v1")
app.include_router(roster.router, prefix="/api/v1")
app.include_router(devices.router, prefix="/api/v1")
app.include_router(edge.router, prefix="/api/v1")
app.include_router(config_router.router, prefix="/api/v1")
app.include_router(tracking.router, prefix="/api/v1")
app.include_router(sos.router, prefix="/api/v1")
app.include_router(statements.router, prefix="/api/v1")
app.include_router(disputes.router, prefix="/api/v1")
app.include_router(driving_flags.router, prefix="/api/v1")
app.include_router(special_trips.router, prefix="/api/v1")
app.include_router(home_pickups.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")

# Van photos (validation, brief 3). Local disk is a prototype choice --
# object storage with signed URLs is the production answer, and that
# belongs in Limitations. Passengers' pictures never go here: door-event
# stills and chat images live under storage/, served behind a role check.
MEDIA_DIR = Path(__file__).resolve().parent.parent / "media"
MEDIA_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(MEDIA_DIR)), name="media")