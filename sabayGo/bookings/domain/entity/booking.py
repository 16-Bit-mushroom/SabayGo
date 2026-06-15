from dataclasses import dataclass, field
from enum import Enum
from sabayGo.core.domain.entity import Entity

# ------ Value Objects ------

class BookingStatus(str, Enum):
    PENDING = 'Pending'
    CONFIRMED = 'Confirmed'
    CANCELLED = 'Cancelled'
    COMPLETED = 'Completed'
    

# ------ Domain Entity -------
@dataclass
class Booking(Entity):
    trip_id: str
    commuter_id: str

    # internal state
    status: BookingStatus = field(default=BookingStatus.PENDING, init=False)

    # Transition Invariants
    def confirm(self):
        if self.status != BookingStatus.PENDING:
            raise ValueError(f"Cannot confirm a booking that is currently {self.status.value}")
        self.status = BookingStatus.CONFIRMED
    
    def cancel(self):
        if self.status in [BookingStatus.CANCELLED, BookingStatus.COMPLETED]:
            raise ValueError(f"Cannot cancel a booking that is already {self.status.value}")
        self.status = BookingStatus.CANCELLED
    
    def complete(self):
        if self.status != BookingStatus.CONFIRMED:
            raise ValueError("Cannot complete a booking unless it is confirmed.")
        self.status = BookingStatus.COMPLETED

        