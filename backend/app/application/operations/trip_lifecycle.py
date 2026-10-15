"""Trip lifecycle: assignment, payment block, start, review, van change,
void, crew, arrival.

Rev 603, change brief section 4. A trip is created from the timetable
days ahead with no van and no Dispatcher; the rest of its life is here:

    Scheduled --start--> Boarding --depart--> Departed --arrive--> Completed
        |                    |
        +---- void (Terminal Manager only) ----> Cancelled

Who may do what is the API's guard (brief 3); the rules are here:

  assign       Terminal Manager, or the Cashier as backup, at the van's
               turn. Validated van, operator and Dispatcher only. Refused
               while the van owes A2Z's share on any statement, unless
               the Terminal Manager overrode this trip's payment block
               (rule 2). A Cashier's assignment alerts the Terminal Manager.
  override     Terminal Manager only, with a written reason: lifts the
               payment block of this one trip, for its assignment and its
               Start ([ASSUMED] one override covers both).
  start        Cashier or Terminal Manager, from `start_opens_minutes`
               before departure, once a van and a Dispatcher are assigned
               and the trip's statement owes nothing -- the Dispatcher
               handed the 15 % over and the Cashier recorded it
               (`finance.statement`) -- or after an override (rule 5).
               A rental (`special_trips`) also waits for its fee, which
               no override lifts (2.5).
               Copies the operator's name and licence and the plate onto
               the trip; warns, never blocks, on an expired licence or a
               phone that is not with the van.
  depart       The Dispatcher, the Cashier or the Terminal Manager:
               `boarding.DepartTripUseCase`, which also locks the list and
               marks a trip that left unpaid (rule 7).
  fall back    The van's GPS leaves the terminal zone (N readings,
               `tracking.nahgm`) with a boarding counted: the system starts
               the trip if nobody did, then departs it (rules 8, 9). There
               is no grace timer. Held for review; with no assigned van,
               'Trip Not Started'. An open 'Not a passenger trip' move
               holds it off (rule 10, `non_passenger`).
  review       Terminal Manager: confirm or change the van of a held
               start; its fare lines then join the statement (rule 11).
  change van   Terminal Manager only, on a started trip, with a reason.
  void         Terminal Manager only, with a reason (rule 12). A rental's
               request closes with its trip (`special_trips`).
  crew         The assigned Dispatcher adds themselves as crew: not a
               boarding, not counted toward the 14 (2.3).
  arrive       The Dispatcher taps Arrived (4.1).

A started trip is not edited quietly: every start, void, van change and
override names who, when and why, and the earlier van and operator go
into `change_note`.

Whether the phone can watch the trip is `edge.evidence`; which trip a
door event belongs to is `edge.ledger`. Not yet: completion when the
count aboard falls to 0 (the per-stop counts arrive with matching, R5).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.edge.evidence import PhoneEvidence
from app.application.edge.ledger import TRIP_REACH, alerted_while_held, release_held
from app.application.finance.statement import ZERO, Statements
from app.application.notifications.service import NotificationService, trip_label
from app.application.operations.boarding import DepartTripUseCase
from app.application.operations.special_trips import close_rental, rental_of
from app.application.scheduling.conflicts import ScheduleConflictChecker
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import (
    BookingStatus,
    BookingType,
    DepartureSource,
    Role,
    StartMode,
    StartReview,
    TripStatus,
)
from app.infrastructure.models import (
    Booking,
    DeviceCheckout,
    NonPassengerMove,
    Notification,
    Operator,
    PassengerEvent,
    Route,
    RouteStop,
    StaffProfile,
    Trip,
    User,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

STARTED = (TripStatus.BOARDING.value, TripStatus.DEPARTED.value,
           TripStatus.COMPLETED.value)
OFFICE = (Role.TERMINAL_MANAGER, Role.CASHIER)
VAN_LEFT = "Trip not started · van left"


@dataclass
class StartOutcome:
    trip: Trip
    warnings: list[str] = field(default_factory=list)


def _now() -> datetime:
    """Naive Manila time, comparable with the naive DATETIME columns."""
    return app_tz.now().replace(tzinfo=None)


class TripLifecycle:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.policies = PolicyRepository(session)
        self.notifications = NotificationService(session)

    # ------------------------------------------------------------ assign
    async def assign(
        self, trip_id: str, *, van_id: str | None, dispatcher_id: str | None, by: User,
    ) -> Trip:
        """Assign the van and the Dispatcher at the van's turn (rule 2).

        The assignment is replaced as a whole. Before the start only:
        after it, the van is changed by the Terminal Manager with a reason.
        """
        if van_id is None and dispatcher_id is None:
            raise ConflictError("Choose a van, a Dispatcher, or both.")
        trip = await self._locked(trip_id)
        if trip.status != TripStatus.SCHEDULED.value:
            raise ConflictError(
                f"This trip is {trip.status}. Only the Terminal Manager changes "
                "the van of a started trip, with a reason."
            )
        await self._assign(trip, van_id=van_id, dispatcher_id=dispatcher_id, by=by)
        await self.session.commit()
        return trip

    async def _assign(
        self, trip: Trip, *, van_id: str | None, dispatcher_id: str | None, by: User,
    ) -> None:
        if van_id is not None:
            van = await self._assignable_van(van_id)
            if van_id != trip.van_id and trip.payment_override_by is None:
                owed = await Statements(self.session).van_balance(van_id)
                if owed > 0:
                    raise ConflictError(
                        f"{van.plate_number} still owes ₱{owed:,.2f} of A2Z's share from "
                        "its last trip. The Cashier records the payment first, or the "
                        "Terminal Manager overrides with a written reason."
                    )
        if dispatcher_id is not None:
            await self._assignable_dispatcher(dispatcher_id)
        await self._no_clash(trip, van_id=van_id, dispatcher_id=dispatcher_id)

        now = _now()
        trip.van_id = van_id
        trip.dispatcher_id = dispatcher_id
        trip.assigned_by = by.user_id
        trip.assigned_at = now
        trip.updated_at = now
        await self.session.flush()
        await self.session.refresh(trip, ["van"])
        # The listed seats' lines follow the trip to its new van.
        await Statements(self.session).sync(trip)
        # The van's phone counts for this trip from now on; what it
        # counted while the van had no trip is matched by time (rule 14).
        await release_held(self.session, trip, now)

        if by.role == Role.CASHIER.value:
            await self.notifications.notify_trip(
                trip=trip, type="assignment_by_cashier",
                title="Assignment by Cashier",
                message=(f"{await self._name(by.user_id)} assigned "
                         f"{trip.van.plate_number if trip.van else 'no van'} and "
                         f"{await self._name(dispatcher_id) if dispatcher_id else 'no Dispatcher'} "
                         f"to {trip_label(trip)}. You can change it before the start."),
                roles=(Role.TERMINAL_MANAGER,),
            )

    # ------------------------------------------------------------- start
    async def start(self, trip_id: str, *, by: User, van_id: str | None = None) -> StartOutcome:
        """The Cashier or the Terminal Manager confirms the assigned van,
        or picks another, and starts the trip (rule 5)."""
        trip = await self._locked(trip_id)
        if trip.status != TripStatus.SCHEDULED.value:
            raise ConflictError(f"This trip is already {trip.status}.")

        now = _now()
        opens_minutes = await self.policies.get_int("start_opens_minutes")
        opens = trip.departure_datetime - timedelta(minutes=opens_minutes)
        if now < opens:
            raise ConflictError(
                f"Start opens at {opens:%H:%M}, {opens_minutes} minutes before departure."
            )

        if van_id is not None and van_id != trip.van_id:
            await self._assign(trip, van_id=van_id, dispatcher_id=trip.dispatcher_id, by=by)
        if trip.van_id is None or trip.dispatcher_id is None:
            raise ConflictError("Assign a van and a Dispatcher before starting this trip.")
        # Confirming the van: it must still be on the roster and validated.
        await self._assignable_van(trip.van_id)
        await self._assignable_dispatcher(trip.dispatcher_id)
        # A rental's fee comes first (2.5); no override lifts it.
        rental = await rental_of(self.session, trip.trip_id) if trip.is_special_trip else None
        if rental is not None and rental.payment_status != "paid":
            raise ConflictError(
                f"The rental fee of ₱{rental.rental_fee:,.2f} is not paid. It is paid before "
                "the van leaves: through the app, or in cash the Dispatcher logs."
            )
        # The 15 % before Start (brief 2.1, hard block).
        if trip.payment_override_by is None:
            money = Statements(self.session)
            statement = await money.sync(trip)
            due = await money.due(statement) if statement is not None else ZERO
            if due > 0:
                raise ConflictError(
                    f"₱{due:,.2f} of A2Z's share is due. The Dispatcher hands it to the "
                    "Cashier, who records it; or the Terminal Manager overrides with a "
                    "written reason."
                )

        warnings = await self._begin(trip, mode=StartMode.MANUAL, by=by, now=now)
        await self.session.commit()
        log.info("Trip %s started by %s.", trip_id, by.user_id)
        return StartOutcome(trip=trip, warnings=warnings)

    # ---------------------------------------------------------- override
    async def override_payment(self, trip_id: str, *, by: User, note: str) -> Trip:
        """The Terminal Manager lifts this trip's payment block, with a
        written reason (brief 2.1). The share stays owed."""
        trip = await self._locked(trip_id)
        if trip.status not in (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value):
            raise ConflictError(f"This trip is {trip.status}; there is no block to lift.")
        note = note.strip()
        if not note:
            raise ConflictError("Write the reason for the override.")
        now = _now()
        trip.payment_override_by = by.user_id
        trip.payment_override_at = now
        trip.payment_override_note = note[:255]
        if trip.payment_status != "paid":
            trip.payment_status = "overridden"
        trip.updated_at = now
        await self.notifications.notify_trip(
            trip=trip, type="payment_block_override", title="Payment block overridden",
            message=f"{await self._name(by.user_id)} let {trip_label(trip)} go ahead without "
                    f"A2Z's share recorded: {note}",
            roles=(Role.CASHIER, Role.TERMINAL_MANAGER), skip_user_id=by.user_id,
        )
        await self.session.commit()
        log.info("Trip %s payment block overridden by %s.", trip_id, by.user_id)
        return trip

    # -------------------------------------------------------------- crew
    async def set_crew(self, trip_id: str, *, by: User, aboard: bool) -> Trip:
        """The assigned Dispatcher adds themselves as crew, once (2.3): the
        door count less the crew is the number aboard."""
        trip = await self._locked(trip_id)
        if trip.dispatcher_id != by.user_id:
            raise ConflictError("Only the Dispatcher assigned to this trip is its crew.")
        if trip.status in (TripStatus.COMPLETED.value, TripStatus.CANCELLED.value):
            raise ConflictError(f"This trip is {trip.status}.")
        trip.crew_aboard = 1 if aboard else 0
        trip.updated_at = _now()
        await self.session.commit()
        log.info("Trip %s: Dispatcher %s %s as crew.", trip_id, by.user_id,
                 "added" if aboard else "removed")
        return trip

    async def fall_back_start(self, trip_id: str, *, why: str) -> Trip | None:
        """The system starts a trip nobody started (rule 7).

        With the assigned van: 'auto_assigned', held for review, and an
        'Unconfirmed Trip Start' alert. With no van: a 'Trip Not Started'
        alert, once, and the trip stays open for the Terminal Manager.
        Returns the started trip, or None.
        """
        trip = await self._locked(trip_id)
        if trip.status != TripStatus.SCHEDULED.value:
            return None

        if trip.van_id is None:
            await self._trip_not_started(trip, why=why)
            await self.session.commit()
            return None

        warnings = await self._begin(trip, mode=StartMode.AUTO_ASSIGNED, by=None, now=_now())
        detail = [f"Nobody started it: {why}. It is left off the daily statement until you review it."]
        if trip.dispatcher_id is None:
            detail.append("No Dispatcher was assigned.")
        await self.notifications.notify_trip(
            trip=trip, type="unconfirmed_trip_start",
            title="Unconfirmed trip start"
                  + (" · No Dispatcher" if trip.dispatcher_id is None else ""),
            message=f"{trip_label(trip)} was started by the system. " + " ".join(detail + warnings),
            roles=(Role.TERMINAL_MANAGER,),
        )
        await self.session.commit()
        log.info("Trip %s started automatically (%s).", trip_id, why)
        return trip

    async def detected_start(
        self, *, van: Van, origin_terminal_id: str, at: datetime, dispatcher_id: str,
    ) -> Trip | None:
        """A checked-out phone saw boardings and its van leave a terminal,
        and the van has no trip at that time (rule 7, 'auto_detected').

        The van is given the trip of its route from that terminal still
        waiting for a van, nearest in time -- the timetable trip nobody
        assigned. The system starts it, held for the Terminal Manager's
        review. A van outside the timetable runs a special trip, entered
        before it leaves (rev 603, 2.5); there is no trip to give it, so
        with none waiting, or a route that cannot be told, the events
        stay held and the Terminal Manager is alerted. Returns the trip,
        or None.
        """
        routes = await self._routes_from(origin_terminal_id, van)
        if len(routes) != 1:
            await self._van_left_without_trip(
                van, "and the system cannot tell its route. Its door events are held: "
                     "create and start its trip.")
            return None
        route_id = routes[0]

        opens = timedelta(minutes=await self.policies.get_int("start_opens_minutes"))
        waiting = (await self.session.execute(
            select(Trip).where(
                Trip.route_id == route_id,
                Trip.status == TripStatus.SCHEDULED.value,
                Trip.van_id.is_(None),
                Trip.departure_datetime <= at + opens,
                Trip.departure_datetime >= at - TRIP_REACH,
            )
        )).scalars().all()
        if not waiting:
            await self._van_left_without_trip(
                van, "and none on its route is waiting for a van. Its door events are "
                     "held: assign it its trip, or enter the special trip it ran.")
            return None
        nearest = min(waiting, key=lambda t: abs(t.departure_datetime - at))
        trip = await self._locked(nearest.trip_id)
        why = f"no van was assigned, and the phone in {van.plate_number} detected its departure"

        # Assigned by the system, so no assigned_by: the review names the person.
        trip.van_id = van.van_id
        trip.dispatcher_id = trip.dispatcher_id or dispatcher_id
        await self.session.flush()
        warnings = await self._begin(trip, mode=StartMode.AUTO_DETECTED, by=None, now=at)
        await self.notifications.notify_trip(
            trip=trip, type="unconfirmed_trip_start", title="Unconfirmed trip start · detected",
            message=f"{trip_label(trip)} was started by the system: {why}. It is left off the "
                    "daily statement until you review it. " + " ".join(warnings),
            roles=(Role.TERMINAL_MANAGER,),
        )
        await self.session.commit()
        log.info("Trip %s started from %s's detected departure.", trip.trip_id, van.plate_number)
        return trip

    async def _van_left_without_trip(self, van: Van, why: str) -> None:
        """'Trip Not Started' about the van, once while its events wait:
        every fix after it left would otherwise raise it again."""
        if not await alerted_while_held(self.session, van.van_id, VAN_LEFT):
            await self.notifications.notify_staff(
                type="trip_not_started", title=VAN_LEFT,
                message=f"{van.plate_number} left a terminal with passengers aboard and no trip, "
                        + why,
                roles=(Role.TERMINAL_MANAGER,), entity=("van", van.van_id),
            )
        await self.session.commit()

    async def _routes_from(self, terminal_id: str, van: Van) -> list[str]:
        """The van's own route, when it starts at this terminal; with no
        registered route, every active route that does."""
        starting = set((await self.session.execute(
            select(RouteStop.route_id)
            .join(Route, Route.route_id == RouteStop.route_id)
            .where(RouteStop.terminal_id == terminal_id, RouteStop.stop_sequence == 1,
                   Route.is_active.is_(True))
        )).scalars().all())
        if van.registered_route_id is not None:
            return [van.registered_route_id] if van.registered_route_id in starting else []
        return sorted(starting)

    async def van_left_origin(self, trip_id: str) -> None:
        """The van's GPS has left the terminal zone (rules 8 and 9).

        With at least one boarding counted, a trip nobody started is
        started by the system, and a started trip departs as 'gps'. A
        boarding is counted from the record (a QR scan or a logged fare)
        or from the phone (a door event). An open 'Not a passenger trip'
        move holds the fallback off (rule 10).
        """
        boarded = (await self.session.execute(
            select(func.count()).select_from(Booking).where(
                Booking.trip_id == trip_id,
                Booking.status == BookingStatus.BOARDED.value,
            )
        )).scalar_one() or (await self.session.execute(
            select(func.count()).select_from(PassengerEvent).where(
                PassengerEvent.trip_id == trip_id, PassengerEvent.event_type == "board",
            )
        )).scalar_one()
        if not boarded:
            return
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            return
        if trip.van_id is not None and (await self.session.execute(
            select(NonPassengerMove.move_id).where(
                NonPassengerMove.van_id == trip.van_id, NonPassengerMove.ended_at.is_(None))
        )).first():
            return
        if trip.status == TripStatus.SCHEDULED.value:
            if await self.fall_back_start(trip_id, why="the van left the terminal") is None:
                return
        if trip.status == TripStatus.BOARDING.value:
            await DepartTripUseCase(self.session).execute(
                trip_id=trip_id, source=DepartureSource.GPS
            )

    # ------------------------------------------------------------ review
    async def review_start(
        self, trip_id: str, *, by: User, van_id: str | None = None, note: str | None = None,
    ) -> Trip:
        """The Terminal Manager confirms or changes the van of a start the
        system made (rule 8). The trip's fare lines join the statement
        from here (step 6)."""
        trip = await self._locked(trip_id)
        if trip.start_review_status != StartReview.PENDING.value:
            raise ConflictError("This trip's start is not waiting for a review.")
        if van_id is not None and van_id != trip.van_id:
            if not (note and note.strip()):
                raise ConflictError("Say why the van is changed.")
            await self._change_van(trip, van_id=van_id, reason=note, by=by)
        now = _now()
        trip.start_review_status = StartReview.REVIEWED.value
        trip.start_reviewed_by = by.user_id
        trip.start_reviewed_at = now
        trip.updated_at = now
        await self.session.flush()
        # Its fare lines join the statement: the held share becomes owed.
        await Statements(self.session).sync(trip)
        await self.session.commit()
        return trip

    # -------------------------------------------------------- change van
    async def change_van(self, trip_id: str, *, by: User, van_id: str, reason: str) -> Trip:
        trip = await self._locked(trip_id)
        if trip.status == TripStatus.SCHEDULED.value:
            raise ConflictError("This trip has not started: change its assignment instead.")
        if trip.status not in STARTED:
            raise ConflictError(f"This trip is {trip.status}.")
        if van_id == trip.van_id:
            raise ConflictError("That is already this trip's van.")
        await self._change_van(trip, van_id=van_id, reason=reason, by=by)
        await self.session.commit()
        return trip

    async def _change_van(self, trip: Trip, *, van_id: str, reason: str, by: User) -> None:
        van = await self._assignable_van(van_id)
        await self._no_clash(trip, van_id=van_id, dispatcher_id=None)
        operator = await self.session.get(Operator, van.operator_id)
        earlier = await self._earlier(trip)

        now = _now()
        trip.van_id = van.van_id
        self._copy_roster(trip, van, operator)
        self._mark_changed(trip, by=by, now=now, note=f"Van changed: {reason.strip()}", earlier=earlier)
        await self.session.flush()
        await self.session.refresh(trip, ["van"])
        await Statements(self.session).sync(trip)

    # -------------------------------------------------------------- void
    async def void(self, trip_id: str, *, by: User, reason: str) -> Trip:
        trip = await self._locked(trip_id)
        if trip.status not in (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value):
            raise ConflictError(f"A trip that is {trip.status} cannot be voided.")
        earlier = await self._earlier(trip)
        now = _now()
        trip.status = TripStatus.CANCELLED.value
        trip.cancellation_reason = reason.strip()[:255]
        self._mark_changed(trip, by=by, now=now, note=f"Voided: {reason.strip()}", earlier=earlier)
        await close_rental(self.session, trip)
        await self.session.flush()
        # A voided trip owes nothing ([OPEN] a trip paid in advance and
        # then voided leaves its statement overpaid).
        await Statements(self.session).sync(trip)

        # Bookings stay as they are (no refunds); their holders are told.
        holders = (await self.session.execute(
            select(Booking.passenger_user_id).where(
                Booking.trip_id == trip.trip_id,
                Booking.booking_type == BookingType.APP.value,
                Booking.passenger_user_id.is_not(None),
                Booking.status.in_([
                    BookingStatus.PENDING.value, BookingStatus.CONFIRMED.value,
                    BookingStatus.CHECKED_IN.value, BookingStatus.BOARDED.value,
                ]),
            )
        )).scalars().all()
        rental = await rental_of(self.session, trip.trip_id) if trip.is_special_trip else None
        renter = [rental.passenger_user_id] if rental and rental.passenger_user_id else []
        await self.notifications.notify_passengers(
            trip=trip, user_ids=list(holders) + renter, title="Your trip was cancelled",
            message=f"The cooperative cancelled {trip_label(trip)}. Please see the "
                    "terminal office about your ticket.",
        )
        await self.session.commit()
        log.info("Trip %s voided by %s.", trip_id, by.user_id)
        return trip

    # ------------------------------------------------------------ arrive
    async def arrive(self, trip_id: str) -> Trip:
        """The Dispatcher taps Arrived: the trip is completed (4.1)."""
        trip = await self._locked(trip_id)
        if trip.status != TripStatus.DEPARTED.value:
            raise ConflictError(f"Only a trip on the road can arrive; this one is {trip.status}.")
        now = _now()
        trip.status = TripStatus.COMPLETED.value
        trip.completed_at = now
        trip.updated_at = now
        await close_rental(self.session, trip)
        await self.session.flush()
        # A silence still open at the end is final now (4.4).
        await PhoneEvidence(self.session).review_coverage(trip)
        await self.session.commit()
        return trip

    # ----------------------------------------------------------- helpers
    async def _locked(self, trip_id: str) -> Trip:
        trip = (await self.session.execute(
            select(Trip).where(Trip.trip_id == trip_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if trip is None:
            raise NotFoundError("Trip not found.")
        return trip

    async def _begin(
        self, trip: Trip, *, mode: StartMode, by: User | None, now: datetime,
    ) -> list[str]:
        """Start the trip and return the warnings for whoever started it."""
        van = await self.session.get(Van, trip.van_id)
        operator = await self.session.get(Operator, van.operator_id)

        trip.status = TripStatus.BOARDING.value
        trip.start_mode = mode.value
        trip.started_by = by.user_id if by else None
        trip.started_at = now
        trip.start_review_status = (
            StartReview.NOT_REQUIRED if mode is StartMode.MANUAL else StartReview.PENDING
        ).value
        self._copy_roster(trip, van, operator)
        trip.updated_at = now
        await self.session.flush()
        await self.session.refresh(trip, ["van"])
        # Door events held because no trip of the van was open (rule 12).
        await release_held(self.session, trip, now)

        warnings: list[str] = []
        skip = by.user_id if by else None

        # Warn, never block (rule 5, assumed): the licence is the
        # operator's, and stopping the van at the door helps no one.
        if operator.license_expiry < now.date():
            text = (f"{operator.full_name}'s driver's licence expired on "
                    f"{operator.license_expiry:%d %b %Y}.")
            warnings.append(text)
            await self.notifications.notify_trip(
                trip=trip, type="system_alert", title="Expired licence on a started trip",
                message=f"{trip_label(trip)}: {text}",
                roles=(Role.TERMINAL_MANAGER,), skip_user_id=skip,
            )

        # The edge phone travels with the van (brief 4.4): with none out,
        # or one that is silent or blind, the trip is Unaudited at once.
        warnings += await PhoneEvidence(self.session).at_start(
            trip, van, now=now, skip_user_id=skip
        )

        # The Dispatcher's phone is on another van: door events will be
        # matched to the van whose phone sends them, by time (rule 11).
        if trip.dispatcher_id is not None:
            theirs = await self._open_checkout(DeviceCheckout.dispatcher_id == trip.dispatcher_id)
            if theirs is not None and theirs.van_id != van.van_id:
                other = await self.session.get(Van, theirs.van_id)
                warnings.append(
                    f"The phone checked out with this Dispatcher is on "
                    f"{other.plate_number}, not {van.plate_number}."
                )
        return warnings

    async def _trip_not_started(self, trip: Trip, *, why: str) -> None:
        """'Trip Not Started', once per trip."""
        already = (await self.session.execute(
            select(Notification.notification_id).where(
                Notification.type == "trip_not_started",
                Notification.related_entity_id == trip.trip_id,
            ).limit(1)
        )).first()
        if already:
            return
        await self.notifications.notify_trip(
            trip=trip, type="trip_not_started", title="Trip not started",
            message=f"{trip_label(trip)}: {why}, and no van is assigned, so the system "
                    "could not start it. Assign a van and start it, or void it.",
            roles=(Role.TERMINAL_MANAGER,),
        )

    async def _open_checkout(self, condition) -> DeviceCheckout | None:
        return (await self.session.execute(
            select(DeviceCheckout).where(condition, DeviceCheckout.returned_at.is_(None))
        )).scalars().first()

    async def _assignable_van(self, van_id: str) -> Van:
        """Only a validated van of a validated member can be picked (rule 6)."""
        van = await self.session.get(Van, van_id)
        if van is None:
            raise NotFoundError("Van not found.")
        if van.validation_status != "validated":
            raise ConflictError(
                f"Van {van.plate_number} is {van.validation_status}, not validated. "
                "The Terminal Manager validates it first."
            )
        if van.operational_status != "active":
            raise ConflictError(f"Van {van.plate_number} is {van.operational_status}.")
        operator = await self.session.get(Operator, van.operator_id)
        if operator.validation_status != "validated" or operator.membership_status != "active":
            raise ConflictError(
                f"{operator.full_name}, who drives {van.plate_number}, is not a "
                "validated, active member."
            )
        return van

    async def _assignable_dispatcher(self, user_id: str) -> User:
        user = await self.session.get(User, user_id)
        if user is None or user.role != Role.DISPATCHER.value:
            raise NotFoundError("Dispatcher not found.")
        if user.account_status != "active":
            raise ConflictError(f"This Dispatcher's account is {user.account_status}.")
        profile = await self.session.get(StaffProfile, user_id)
        if profile is None or profile.validation_status != "validated":
            raise ConflictError(
                "This Dispatcher is not validated. The Terminal Manager validates them first."
            )
        return user

    async def _no_clash(
        self, trip: Trip, *, van_id: str | None, dispatcher_id: str | None,
    ) -> None:
        clashes = await ScheduleConflictChecker(self.session).find_conflicts(
            route_id=trip.route_id,
            departure=trip.departure_datetime,
            van_id=van_id,
            dispatcher_id=dispatcher_id,
            exclude_trip_id=trip.trip_id,
        )
        if clashes:
            raise ConflictError(clashes[0].message)

    @staticmethod
    def _copy_roster(trip: Trip, van: Van, operator: Operator) -> None:
        """Fixed on the trip, so a later roster edit cannot rewrite it."""
        trip.driver_name = operator.full_name
        trip.driver_license_no = operator.license_number
        trip.van_plate_number = van.plate_number

    async def _earlier(self, trip: Trip) -> str:
        if trip.van_id is None:
            return ""
        plate = trip.van_plate_number
        name = trip.driver_name
        if plate is None or name is None:
            van = await self.session.get(Van, trip.van_id)
            operator = await self.session.get(Operator, van.operator_id)
            plate, name = plate or van.plate_number, name or operator.full_name
        return f"earlier van {plate}, operator {name}"

    @staticmethod
    def _mark_changed(trip: Trip, *, by: User, now: datetime, note: str, earlier: str) -> None:
        """Who, when and why; the earlier van and operator always survive
        the 255-character column."""
        suffix = f" ({earlier})" if earlier else ""
        trip.changed_by = by.user_id
        trip.changed_at = now
        trip.change_note = note[: 255 - len(suffix)] + suffix
        trip.updated_at = now

    async def _name(self, user_id: str) -> str:
        profile = await self.session.get(StaffProfile, user_id)
        return f"{profile.first_name} {profile.last_name}" if profile else "Someone"

