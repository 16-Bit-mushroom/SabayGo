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

from app.api.v1 import audits, auth, bookings, operations, payments, trips
from app.config import settings
from app.core.db import engine
from app.core.exceptions import DomainError

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
    yield
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
app.include_router(audits.router, prefix="/api/v1")

# Blurred audit snapshots. Local disk is a prototype choice -- object
# storage with signed URLs and a retention policy is the production
# answer, and that belongs in Limitations.
MEDIA_DIR = Path(__file__).resolve().parent.parent / "media"
MEDIA_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(MEDIA_DIR)), name="media")
