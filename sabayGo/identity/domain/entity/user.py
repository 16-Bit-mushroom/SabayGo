from sabayGo.core.domain.entity import Entity
from dataclasses import dataclass, field
from datetime import date
from enum import Enum
from typing import Optional

#------------ VALUE OBJECTS --------------

class Role(str, Enum):
    COMMUTER = 'Commuter'
    DRIVER = 'Driver'
    ADMIN = 'Admin'


@dataclass(frozen=True)
class Email:
    value: str

    def __post_init__(self):
        if not self.value.endswith(".edu.ph"):
            raise ValueError("Email must be a valid university .edu.ph address.")

@dataclass(frozen=True)
class PhoneNumber:
    value: str

    def __post_init__(self):
        # Cleans up accidental spaces
        # Note: 'object.__setattr__' is needed to modify frozen dataclasses in __post_init__
        object.__setattr__(self, 'value', self.value.strip())
        
        # Basic Philippine mobile number validation
        is_standard = self.value.startswith("09") and len(self.value) == 11
        is_intl = self.value.startswith("+639") and len(self.value) == 13
        
        if not (is_standard or is_intl):
            raise ValueError("Must be a valid Philippine mobile number (e.g., 09123456789).")


@dataclass(frozen=True)
class BirthDate:
    value: date

    def __post_init__(self):
        today = date.today()
        
        # 1. The Time Traveler Invariant
        if self.value > today:
            raise ValueError("Birth date cannot be in the future.")
        
        # Calculate age
        age = today.year - self.value.year - ((today.month, today.day) < (self.value.month, self.value.day))
        
        # 2. The Minimum Age Invariant
        if age < 18:
            raise ValueError("User must be at least 18 years old to register.")
            
        # 3. The Maximum Logical Age Invariant
        if age > 120:
            raise ValueError("Please enter a valid birth date.")
        
@dataclass(frozen=True)
class EmergencyContact:
    name: str
    phone: PhoneNumber

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("Emergency contact name cannot be empty.")

#--------------- DOMAIN ENTITY ----------------
@dataclass
class User(Entity):
    # Reqruired field first
    email: Email
    first_name: str
    last_name: str
    birth_date: BirthDate 
    phone_number: PhoneNumber
    emergency_contact: EmergencyContact

    # Optional fields (with defaults) come after
    middle_name: Optional[str] = None

    # Internal state fields (init=False) come last
    role: Role = field(default=Role.COMMUTER, init=False)
    is_active: bool = field(default=True, init=False)


    # Creation invariants
    def __post_init__(self):
        if not self.first_name.strip():
            raise ValueError("First name cannot be empty.")
        if not self.last_name.strip():
            raise ValueError("Last name cannot be empty.")

    # Domain behavior, business rule or also known as invariants
    def upgrade_to_driver(self):
        """Upgrades a commuter to a driver and attaches their profile.

        This method enforces state transition invariants. It guarantees that 
        suspended users cannot bypass bans, and prevents duplicate upgrades.

        Args:
            profile (DriverProfile): The validated KYC profile containing 
                license and vehicle details.

        Raises:
            ValueError: If the user is currently suspended.
            ValueError: If the user already has the DRIVER role.
            ValueError: If a valid DriverProfile is not provided.
        """

        if not self.is_active:
            raise ValueError("Cannot upgrade suspended user.")
        
        if self.role == 'Driver':
            raise ValueError("User is already a driver.")

        self.role = Role.DRIVER

    def suspend(self):
        if not self.is_active:
            raise ValueError("User is already suspended")
        self.is_active = False
        
    def restore(self):
        if self.is_active:
            raise ValueError("User is already active")
        self.is_active = True

        if self.role == Role.DRIVER:
            raise ValueError("User is already a driver")
        self.role = Role.DRIVER
