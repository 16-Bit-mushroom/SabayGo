"""SQLAlchemy ORM models.

These map onto the tables created by db/migrations/001-006. The migrations
remain the source of truth -- these classes describe that schema, they do
not generate it. Never run create_all() against a real database.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.mysql import DATETIME, TINYINT
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


UUID_PK = String(36)


# ======================================================================
# Reference
# ======================================================================
class CooperativePolicy(Base):
    __tablename__ = "cooperative_policies"

    policy_key: Mapped[str] = mapped_column(String(64), primary_key=True)
    policy_value: Mapped[str] = mapped_column(String(255))
    data_type: Mapped[str] = mapped_column(String(16))
    description: Mapped[str] = mapped_column(String(255))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class Terminal(Base):
    __tablename__ = "terminals"

    terminal_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    terminal_name: Mapped[str] = mapped_column(String(255))
    city: Mapped[str] = mapped_column(String(100))
    location_address: Mapped[str | None] = mapped_column(String(255))
    latitude: Mapped[Decimal] = mapped_column(Numeric(8, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    geofence_radius_m: Mapped[int | None]
    is_staffed: Mapped[bool] = mapped_column(Boolean, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class Route(Base):
    __tablename__ = "routes"

    route_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    route_code: Mapped[str] = mapped_column(String(32), unique=True)
    route_name: Mapped[str] = mapped_column(String(255))
    ltfrb_case_no: Mapped[str | None] = mapped_column(String(64))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))

    stops: Mapped[list[RouteStop]] = relationship(
        back_populates="route", order_by="RouteStop.stop_sequence", lazy="selectin"
    )


class RouteStop(Base):
    __tablename__ = "route_stops"

    route_stop_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    route_id: Mapped[str] = mapped_column(ForeignKey("routes.route_id"))
    terminal_id: Mapped[str] = mapped_column(ForeignKey("terminals.terminal_id"))
    stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    offset_minutes: Mapped[int] = mapped_column(SmallInteger, default=0)

    route: Mapped[Route] = relationship(back_populates="stops")
    terminal: Mapped[Terminal] = relationship(lazy="joined")


class FareMatrix(Base):
    __tablename__ = "fare_matrix"

    fare_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    route_id: Mapped[str] = mapped_column(ForeignKey("routes.route_id"))
    from_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    to_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    fare_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    effective_from: Mapped[dt.date] = mapped_column(Date)


# ======================================================================
# Identity
# ======================================================================
class User(Base):
    __tablename__ = "users"

    user_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    phone_number: Mapped[str | None] = mapped_column(String(20), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(16))
    account_status: Mapped[str] = mapped_column(String(16), default="active")
    fcm_token: Mapped[str | None] = mapped_column(String(512))
    last_login_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))

    passenger_profile: Mapped[PassengerProfile | None] = relationship(
        back_populates="user", lazy="selectin"
    )
    staff_profile: Mapped[StaffProfile | None] = relationship(
        back_populates="user", lazy="selectin"
    )


class PassengerProfile(Base):
    __tablename__ = "passenger_profiles"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), primary_key=True)
    first_name: Mapped[str] = mapped_column(String(70))
    middle_name: Mapped[str | None] = mapped_column(String(70))
    last_name: Mapped[str] = mapped_column(String(100))
    home_address: Mapped[str | None] = mapped_column(String(255))
    gender: Mapped[str | None] = mapped_column(String(16))
    emergency_contact_name: Mapped[str | None] = mapped_column(String(150))
    emergency_contact_relation: Mapped[str | None] = mapped_column(String(50))
    emergency_contact_number: Mapped[str | None] = mapped_column(String(20))
    avatar_url: Mapped[str | None] = mapped_column(String(512))
    trust_rating: Mapped[Decimal] = mapped_column(Numeric(2, 1), default=5.0)

    user: Mapped[User] = relationship(back_populates="passenger_profile")


class StaffProfile(Base):
    __tablename__ = "staff_profiles"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), primary_key=True)
    first_name: Mapped[str] = mapped_column(String(70))
    middle_name: Mapped[str | None] = mapped_column(String(70))
    last_name: Mapped[str] = mapped_column(String(100))
    birth_date: Mapped[dt.date | None] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(16))
    home_address: Mapped[str | None] = mapped_column(String(255))
    profile_pic_url: Mapped[str | None] = mapped_column(String(512))
    cooperative_name: Mapped[str | None] = mapped_column(String(255))
    assigned_terminal_id: Mapped[str | None] = mapped_column(
        ForeignKey("terminals.terminal_id")
    )
    employment_status: Mapped[str] = mapped_column(String(16), default="active")

    user: Mapped[User] = relationship(back_populates="staff_profile")


class DriverCredential(Base):
    __tablename__ = "driver_credentials"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), primary_key=True)
    license_number: Mapped[str] = mapped_column(String(64), unique=True)
    license_expiry_date: Mapped[dt.date] = mapped_column(Date)
    cttmo_id_number: Mapped[str | None] = mapped_column(String(64))
    cttmo_id_photo_url: Mapped[str | None] = mapped_column(String(512))


class PassengerSettings(Base):
    __tablename__ = "passenger_settings"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"), primary_key=True)
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    tailored_schedules: Mapped[bool] = mapped_column(Boolean, default=True)
    trip_updates: Mapped[bool] = mapped_column(Boolean, default=True)


class SavedDestination(Base):
    __tablename__ = "saved_destinations"

    destination_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    label: Mapped[str] = mapped_column(String(255))
    terminal_id: Mapped[str | None] = mapped_column(ForeignKey("terminals.terminal_id"))
    address: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


# ======================================================================
# Fleet
# ======================================================================
class Van(Base):
    __tablename__ = "vans"

    van_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    plate_number: Mapped[str] = mapped_column(String(20), unique=True)
    cpc_case_no: Mapped[str | None] = mapped_column(String(64))
    cpc_number: Mapped[str | None] = mapped_column(String(64))
    brand: Mapped[str | None] = mapped_column(String(64))
    model: Mapped[str | None] = mapped_column(String(64))
    color: Mapped[str | None] = mapped_column(String(32))
    seat_capacity: Mapped[int] = mapped_column(TINYINT(unsigned=True), default=14)
    operational_status: Mapped[str] = mapped_column(String(16), default="active")
    registered_route_id: Mapped[str | None] = mapped_column(
        ForeignKey("routes.route_id")
    )
    has_cabin_camera: Mapped[bool] = mapped_column(Boolean, default=False)
    camera_installed_at: Mapped[dt.date | None] = mapped_column(Date)
    camera_device_id: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


# ======================================================================
# Scheduling
# ======================================================================
class ScheduleTemplate(Base):
    __tablename__ = "schedule_templates"

    template_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    route_id: Mapped[str] = mapped_column(ForeignKey("routes.route_id"))
    departure_time: Mapped[dt.time]
    days_of_week: Mapped[str] = mapped_column(String(7), default="1111111")
    default_van_id: Mapped[str | None] = mapped_column(ForeignKey("vans.van_id"))
    default_driver_id: Mapped[str | None] = mapped_column(ForeignKey("users.user_id"))
    default_conductor_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id")
    )
    trip_label: Mapped[str | None] = mapped_column(String(64))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    valid_from: Mapped[dt.date] = mapped_column(Date)
    valid_until: Mapped[dt.date | None] = mapped_column(Date)
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class Trip(Base):
    __tablename__ = "trips"

    trip_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    template_id: Mapped[str | None] = mapped_column(
        ForeignKey("schedule_templates.template_id")
    )
    route_id: Mapped[str] = mapped_column(ForeignKey("routes.route_id"))
    service_date: Mapped[dt.date] = mapped_column(Date)
    departure_datetime: Mapped[dt.datetime] = mapped_column(DateTime)
    van_id: Mapped[str | None] = mapped_column(ForeignKey("vans.van_id"))
    driver_id: Mapped[str | None] = mapped_column(ForeignKey("users.user_id"))
    conductor_id: Mapped[str | None] = mapped_column(ForeignKey("users.user_id"))
    trip_label: Mapped[str | None] = mapped_column(String(64))
    is_special_trip: Mapped[bool] = mapped_column(Boolean, default=False)
    seat_capacity: Mapped[int] = mapped_column(TINYINT(unsigned=True), default=14)
    advance_booking_seat_cap: Mapped[int] = mapped_column(
        TINYINT(unsigned=True), default=10
    )
    reschedule_cutoff_hours: Mapped[int] = mapped_column(SmallInteger, default=6)
    status: Mapped[str] = mapped_column(String(16), default="scheduled")
    cancellation_reason: Mapped[str | None] = mapped_column(String(255))
    departed_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    completed_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))

    route: Mapped[Route] = relationship(lazy="selectin")
    van: Mapped[Van | None] = relationship(lazy="selectin")


class TripLeg(Base):
    __tablename__ = "trip_legs"

    trip_leg_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    leg_sequence: Mapped[int] = mapped_column(SmallInteger)
    from_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    to_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    departs_at: Mapped[dt.datetime | None] = mapped_column(DateTime)


class SeatInventory(Base):
    """One row per (trip, seat, leg). The table the locking runs against."""

    __tablename__ = "seat_inventory"

    seat_inventory_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    seat_number: Mapped[int] = mapped_column(TINYINT(unsigned=True))
    leg_sequence: Mapped[int] = mapped_column(SmallInteger)
    status: Mapped[str] = mapped_column(String(16), default="available")
    booking_id: Mapped[str | None] = mapped_column(String(36))
    hold_expires_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))

    __table_args__ = (
        UniqueConstraint("trip_id", "seat_number", "leg_sequence", name="uq_seat_leg"),
        Index(
            "idx_seat_allocation", "trip_id", "leg_sequence", "status", "seat_number"
        ),
    )


# ======================================================================
# Transactions
# ======================================================================
class Booking(Base):
    __tablename__ = "bookings"

    booking_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    ticket_number: Mapped[str] = mapped_column(String(32), unique=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    passenger_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.user_id"))
    walkin_name: Mapped[str | None] = mapped_column(String(150))
    walkin_phone: Mapped[str | None] = mapped_column(String(20))
    walkin_wants_receipt: Mapped[bool] = mapped_column(Boolean, default=False)
    booking_type: Mapped[str] = mapped_column(String(16))
    is_roadside_pickup: Mapped[bool] = mapped_column(Boolean, default=False)
    pickup_landmark: Mapped[str | None] = mapped_column(String(255))
    boarding_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    alighting_stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    seat_number: Mapped[int] = mapped_column(TINYINT(unsigned=True))
    fare_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    fare_is_manual: Mapped[bool] = mapped_column(Boolean, default=False)
    fare_note: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    qr_payload: Mapped[str | None] = mapped_column(String(255), unique=True)
    rescheduled_from_booking_id: Mapped[str | None] = mapped_column(String(36))
    reschedule_count: Mapped[int] = mapped_column(TINYINT(unsigned=True), default=0)
    booked_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    cancelled_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class Payment(Base):
    __tablename__ = "payments"

    payment_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    booking_id: Mapped[str] = mapped_column(ForeignKey("bookings.booking_id"))
    provider: Mapped[str] = mapped_column(String(20))
    method: Mapped[str | None] = mapped_column(String(20))
    # Set when this fare is included in an end-of-trip cash handover.
    remittance_id: Mapped[str | None] = mapped_column(String(36))
    provider_ref_id: Mapped[str | None] = mapped_column(String(128))
    provider_event_id: Mapped[str | None] = mapped_column(String(128), unique=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    paid_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    raw_payload: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class CheckIn(Base):
    __tablename__ = "check_ins"

    check_in_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    booking_id: Mapped[str] = mapped_column(ForeignKey("bookings.booking_id"))
    terminal_id: Mapped[str] = mapped_column(ForeignKey("terminals.terminal_id"))
    latitude: Mapped[Decimal] = mapped_column(Numeric(8, 6))
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    gps_accuracy_m: Mapped[Decimal | None] = mapped_column(Numeric(6, 2))
    distance_m: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    geofence_radius_m: Mapped[int]
    is_within_geofence: Mapped[bool] = mapped_column(Boolean)
    is_within_window: Mapped[bool] = mapped_column(Boolean)
    rejection_reason: Mapped[str | None] = mapped_column(String(255))
    checked_in_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class BoardingScan(Base):
    __tablename__ = "boarding_scans"

    scan_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    booking_id: Mapped[str] = mapped_column(ForeignKey("bookings.booking_id"))
    scanned_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    result: Mapped[str] = mapped_column(String(24))
    scanned_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    client_recorded_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    synced_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))


# ======================================================================
# Audit
# ======================================================================
class Yolov8AuditLog(Base):
    __tablename__ = "yolov8_audit_logs"

    audit_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    leg_sequence: Mapped[int | None] = mapped_column(SmallInteger)
    triggered_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id")
    )
    trigger_type: Mapped[str] = mapped_column(String(16), default="manual")
    visual_count: Mapped[int] = mapped_column(SmallInteger)
    booked_count: Mapped[int] = mapped_column(SmallInteger)
    variance: Mapped[int] = mapped_column(SmallInteger)
    model_version: Mapped[str | None] = mapped_column(String(32))
    inference_ms: Mapped[int | None]
    confidence_avg: Mapped[Decimal | None] = mapped_column(Numeric(4, 3))
    snapshot_url: Mapped[str | None] = mapped_column(String(512))
    resolution_status: Mapped[str] = mapped_column(String(16), default="pending")
    resolved_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.user_id"))
    resolved_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    resolution_notes: Mapped[str | None] = mapped_column(String(512))
    captured_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class Notification(Base):
    __tablename__ = "notifications"

    notification_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    audience: Mapped[str] = mapped_column(String(16))
    type: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(100))
    message: Mapped[str] = mapped_column(String(500))
    related_entity_type: Mapped[str | None] = mapped_column(String(32))
    related_entity_id: Mapped[str | None] = mapped_column(String(36))
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    fcm_message_id: Mapped[str | None] = mapped_column(String(128))
    delivery_status: Mapped[str] = mapped_column(String(16), default="queued")
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))


class DriverHeadcount(Base):
    __tablename__ = "driver_headcounts"

    headcount_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    stop_sequence: Mapped[int] = mapped_column(SmallInteger)
    confirmed_count: Mapped[int] = mapped_column(SmallInteger)
    manifest_count: Mapped[int] = mapped_column(SmallInteger)
    variance: Mapped[int] = mapped_column(SmallInteger)
    confirmed_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    confirmed_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    client_recorded_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    synced_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))


class CashRemittance(Base):
    """End-of-trip cash handover from crew to office.

    `expected_amount` is computed from the crew member's own cash bookings
    and never typed in -- the figure a person is measured against must not
    be editable by that person.
    """

    __tablename__ = "cash_remittances"

    remittance_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    collected_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    expected_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    declared_amount: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    received_amount: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    variance: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    submitted_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    received_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    received_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id")
    )
    notes: Mapped[str | None] = mapped_column(String(512))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
