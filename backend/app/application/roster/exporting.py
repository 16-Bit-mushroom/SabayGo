"""Member-roster export (brief 8): any list as CSV or PDF, logged.

Two purposes have their own shape. A backup carries the import
template's columns under the same names, so a backup file can be
imported again, plus each record's status. The LTFRB cross-check is the
van list the regional office compares against its own records: plate,
CPC case number and number, operator, validation status and date. There
is no connection to LTFRB's systems; the office hands over the file.
"""

from __future__ import annotations

import csv
import io
import uuid

from fpdf import FPDF
from fpdf.fonts import FontFace
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.identity.naming import display_name
from app.core.exceptions import InvalidInputError
from app.core.timezone import now
from app.domain.enums import Role
from app.infrastructure.models import (
    DataTransfer,
    Operator,
    Route,
    StaffProfile,
    User,
    Van,
)

RECORD_TYPES = ("operators", "vans", "dispatchers")
PURPOSES = ("backup", "ltfrb_check", "other")

_TITLES = {
    "operators": "Operators",
    "vans": "Vans",
    "dispatchers": "Dispatchers",
}


def _s(value: object) -> str:
    if value is None:
        return ""
    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d")
    return str(value)


async def _rows(
    session: AsyncSession, record_type: str, purpose: str
) -> tuple[list[str], list[list[str]]]:
    if record_type == "operators":
        headers = ["full_name", "contact_number", "email", "license_number",
                   "license_expiry", "membership_status", "validation_status",
                   "validated_on", "plate_number"]
        result = await session.execute(
            select(Operator, Van.plate_number)
            .outerjoin(Van, Van.operator_id == Operator.operator_id)
            .order_by(Operator.full_name)
        )
        return headers, [
            [_s(v) for v in (op.full_name, op.contact_number, op.email,
                             op.license_number, op.license_expiry,
                             op.membership_status, op.validation_status,
                             op.validated_at, plate)]
            for op, plate in result.all()
        ]

    if record_type == "vans":
        result = await session.execute(
            select(Van, Operator, Route.route_code)
            .join(Operator, Operator.operator_id == Van.operator_id)
            .outerjoin(Route, Route.route_id == Van.registered_route_id)
            .order_by(Van.plate_number)
        )
        rows = result.all()
        if purpose == "ltfrb_check":
            headers = ["plate_number", "cpc_case_no", "cpc_number", "operator",
                       "validation_status", "validated_on"]
            return headers, [
                [_s(v) for v in (van.plate_number, van.cpc_case_no, van.cpc_number,
                                 op.full_name, van.validation_status, van.validated_at)]
                for van, op, _ in rows
            ]
        headers = ["plate_number", "operator_license_number", "cpc_case_no",
                   "cpc_number", "brand", "model", "color", "seat_capacity",
                   "registered_route", "operator", "operational_status",
                   "validation_status", "validated_on"]
        return headers, [
            [_s(v) for v in (van.plate_number, op.license_number, van.cpc_case_no,
                             van.cpc_number, van.brand, van.model, van.color,
                             van.seat_capacity, code, op.full_name,
                             van.operational_status, van.validation_status,
                             van.validated_at)]
            for van, op, code in rows
        ]

    headers = ["last_name", "first_name", "phone_number", "email",
               "employment_status", "validation_status", "validated_on"]
    result = await session.execute(
        select(User, StaffProfile)
        .join(StaffProfile, StaffProfile.user_id == User.user_id)
        .where(User.role == Role.DISPATCHER.value)
        .order_by(StaffProfile.last_name, StaffProfile.first_name)
    )
    return headers, [
        [_s(v) for v in (p.last_name, p.first_name, u.phone_number, u.email,
                         p.employment_status, p.validation_status, p.validated_at)]
        for u, p in result.all()
    ]


def _csv(headers: list[str], rows: list[list[str]]) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(headers)
    w.writerows(rows)
    return buf.getvalue().encode("utf-8-sig")  # BOM so Excel reads UTF-8


def _latin(text: str) -> str:
    # The PDF core fonts are Latin-1: 'ñ' prints, anything wider becomes '?'.
    return text.encode("latin-1", "replace").decode("latin-1")


def _pdf(title: str, subtitle: str, headers: list[str], rows: list[list[str]]) -> bytes:
    pdf = FPDF(orientation="L", format="A4")
    pdf.set_auto_page_break(auto=True, margin=12)
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 13)
    pdf.cell(0, 8, _latin(title), new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", size=8)
    pdf.cell(0, 5, _latin(subtitle), new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    with pdf.table(headings_style=FontFace(emphasis="BOLD"), line_height=5,
                   text_align="LEFT") as table:
        head = table.row()
        for h in headers:
            head.cell(h.replace("_", " "))
        for values in rows:
            row = table.row()
            for v in values:
                row.cell(_latin(v))
    return bytes(pdf.output())


async def export(
    session: AsyncSession, record_type: str, fmt: str, purpose: str, user: User
) -> tuple[str, str, bytes]:
    """(file name, media type, bytes). The export is logged; the caller commits."""
    if purpose == "ltfrb_check" and record_type != "vans":
        raise InvalidInputError("The LTFRB cross-check list is a list of vans.")
    headers, rows = await _rows(session, record_type, purpose)

    stamp = now().replace(tzinfo=None)
    name = f"sabaygo_{record_type}_{purpose}_{stamp:%Y%m%d_%H%M}.{fmt}"
    if fmt == "csv":
        body, media = _csv(headers, rows), "text/csv; charset=utf-8"
    else:
        label = "LTFRB cross-check" if purpose == "ltfrb_check" else purpose.capitalize()
        title = f"A2Z Transport Cooperative - {_TITLES[record_type]} ({label})"
        subtitle = (f"{len(rows)} records. Exported {stamp:%Y-%m-%d %H:%M} by "
                    f"{display_name(user)} from SabayGo.")
        body, media = _pdf(title, subtitle, headers, rows), "application/pdf"

    session.add(DataTransfer(
        transfer_id=str(uuid.uuid4()),
        direction="export",
        record_type=record_type,
        file_name=name,
        file_format=fmt,
        export_purpose=purpose,
        rows_in_file=len(rows),
        performed_by=user.user_id,
        performed_at=stamp,
    ))
    return name, media, body
