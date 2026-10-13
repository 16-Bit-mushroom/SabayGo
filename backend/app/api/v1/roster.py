"""Member-roster import and export (brief 8), for the Terminal Manager
and the Cashier. The records themselves, and their validation, are in
fleet.py; the rules are in application/roster."""

from __future__ import annotations

import datetime as dt
from typing import Annotated

from fastapi import APIRouter, Depends, File, Query, UploadFile
from fastapi import Path as PathParam
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel
from sqlalchemy import select

from app.api.v1.deps import OFFICE, CurrentUser, SessionDep
from app.application.identity.naming import display_name
from app.application.roster import exporting, importing
from app.core.exceptions import NotFoundError
from app.infrastructure.models import DataTransfer, StaffProfile

router = APIRouter(prefix="/roster", tags=["roster"], dependencies=[Depends(OFFICE)])

Importable = Annotated[str, PathParam(pattern="^(operators|vans)$")]
Exportable = Annotated[str, PathParam(pattern="^(operators|vans|dispatchers)$")]

_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


class TransferOut(BaseModel):
    transfer_id: str
    direction: str
    record_type: str
    file_name: str
    file_format: str
    export_purpose: str | None
    rows_in_file: int
    rows_accepted: int
    rows_rejected: int
    error_file_url: str | None
    performed_by: str
    performed_by_name: str | None
    performed_at: dt.datetime


class ImportResult(BaseModel):
    record_type: str
    rows_in_file: int
    rows_passing: int
    rows_failing: int
    rows: list[dict]
    # Set once the import is saved; a preview has none.
    transfer: TransferOut | None = None


def _transfer_out(t: DataTransfer, name: str | None) -> TransferOut:
    fields = {c: getattr(t, c) for c in TransferOut.model_fields if hasattr(DataTransfer, c)}
    return TransferOut(**fields, performed_by_name=name)


def _result(record_type: str, rows: list[importing.RowResult],
            transfer: TransferOut | None = None) -> ImportResult:
    passing = sum(1 for r in rows if r.record is not None)
    return ImportResult(
        record_type=record_type,
        rows_in_file=len(rows),
        rows_passing=passing,
        rows_failing=len(rows) - passing,
        rows=[r.as_dict() for r in rows],
        transfer=transfer,
    )


def _attachment(name: str) -> dict:
    return {"Content-Disposition": f'attachment; filename="{name}"'}


@router.get("/templates/{record_type}")
async def download_template(
    record_type: Importable, format: str = Query("xlsx", pattern="^(csv|xlsx)$")
) -> Response:
    """The blank template to copy the binder into."""
    return Response(
        content=importing.template(record_type, format),
        media_type="text/csv; charset=utf-8" if format == "csv" else _XLSX,
        headers=_attachment(f"sabaygo_{record_type}_template.{format}"),
    )


@router.post("/import/{record_type}/preview", response_model=ImportResult)
async def preview_import(
    record_type: Importable, session: SessionDep, file: UploadFile = File(...)
) -> ImportResult:
    """Every row with the reasons it fails. Saves nothing."""
    data = await file.read(importing.MAX_BYTES + 1)
    rows = await importing.preview(session, record_type, file.filename or "", data)
    return _result(record_type, rows)


@router.post("/import/{record_type}", response_model=ImportResult, status_code=201)
async def confirm_import(
    record_type: Importable, session: SessionDep, user: CurrentUser,
    file: UploadFile = File(...),
) -> ImportResult:
    """Save the passing rows, Pending until the Terminal Manager validates
    them. The same file as the preview is sent again and re-checked."""
    data = await file.read(importing.MAX_BYTES + 1)
    transfer, rows = await importing.commit(
        session, record_type, file.filename or "", data, user
    )
    return _result(record_type, rows, _transfer_out(transfer, display_name(user)))


@router.get("/export/{record_type}")
async def export_list(
    record_type: Exportable,
    session: SessionDep,
    user: CurrentUser,
    format: str = Query("csv", pattern="^(csv|pdf)$"),
    purpose: str = Query("backup", pattern="^(backup|ltfrb_check|other)$"),
) -> Response:
    name, media, body = await exporting.export(session, record_type, format, purpose, user)
    await session.commit()
    return Response(content=body, media_type=media, headers=_attachment(name))


@router.get("/transfers", response_model=list[TransferOut])
async def list_transfers(
    session: SessionDep, limit: int = Query(50, ge=1, le=500)
) -> list[TransferOut]:
    """The import and export log, newest first."""
    result = await session.execute(
        select(DataTransfer, StaffProfile.first_name, StaffProfile.last_name)
        .outerjoin(StaffProfile, StaffProfile.user_id == DataTransfer.performed_by)
        .order_by(DataTransfer.performed_at.desc())
        .limit(limit)
    )
    return [
        _transfer_out(t, f"{first} {last}" if first else None)
        for t, first, last in result.all()
    ]


@router.get("/transfers/{transfer_id}/rejected")
async def download_rejected(transfer_id: str, session: SessionDep) -> FileResponse:
    """An import's failing rows with a reason column: correct the rows and
    upload this file again as it is."""
    transfer = await session.get(DataTransfer, transfer_id)
    path = importing.rejected_path(transfer_id)
    if transfer is None or transfer.error_file_url is None or not path.is_file():
        raise NotFoundError("This import has no rejected rows on file.")
    return FileResponse(
        path, media_type="text/csv; charset=utf-8",
        filename=f"rejected_{transfer.file_name.rsplit('.', 1)[0]}.csv",
    )
