from sabayGo.core.domain.entity import Entity
from dataclasses import dataclass, field
from enum import Enum
from datetime import datetime
from sabayGo.trip.domain.value_objects.node import Node

#----------- Value Objects ------------
class TripStatus(str, Enum):
    SCHEDULED = "Scheduled"
    IN_PROGRESS = "In_Progress"
    COMPLETED = "Completed"
    CANCELLED = "Cancelled"

@dataclass
class Trip(Entity):
    driver_id: str
    origin: Node
    destination: Node
    departure_time: datetime
    total_seats: str

    # internal state
    available_seats: int = field(init=False)
    status: TripStatus = field(default=TripStatus.SCHEDULED, init=False)

    # Creation Invariants
    def __post_init__(self):
        # Teleportation guard
        if self.origin.latitude == self.origin.latitude and self.origin.longitude == self.origin.longitude:
            raise ValueError("Origin and destination cannot be the exact same location.")
        
        # DeLorean Guard
        if self.departure_time <= datetime.now():
            raise ValueError("Departure time must be in the future.")
        
        # Ghost Car Guard
        if self.total_seats <= 0:
            raise ValueError("A trip must offer at least one seat.")
        
        self.available_seats = self.total_seats
    
    # State Transition Invariants
    def start_trip(self):
        if self.status != TripStatus.SCHEDULED:
            raise ValueError(f"Cannot start a trip that is currently {self.status.value}.")
        self.status = TripStatus.IN_PROGRESS

    def complete_trip(self):
        if self.status != TripStatus.IN_PROGRESS:
            raise ValueError("Cannot complete a trip that is not in progress.")
        self.status = TripStatus.COMPLETED

    def cancel_trip(self):
        if self.status in [TripStatus.COMPLETED, TripStatus.CANCELLED]:
            raise ValueError(f"Cannot cancel a trip that is already {self.status.value}.")
        self.status = TripStatus.CANCELLED

    # CAPACITY INVARIANTS
    def reserve_seat(self):
        if self.status != TripStatus.SCHEDULED:
            raise ValueError("Can only reserve seats for scheduled trips.")
        if self.available_seats <= 0:
            raise ValueError("No available seats left on this trip.")
        self.available_seats -= 1

    def free_seat(self):
        if self.available_seats >= self.total_seats:
            raise ValueError("Cannot free a seat; the vehicle is already empty.")
        self.available_seats += 1