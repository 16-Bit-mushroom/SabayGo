from dataclasses import dataclass, field
from enum import Enum
from sabayGo.core.domain.entity import Entity
import re

class KycStatus(str, Enum):
    PENDING = "Pending"
    APPROVED = "Approved"
    REJECTED = "Rejected"

@dataclass(frozen=True)
class LicenseNumber:
    value: str

    def __post_init__(self):
        # Removes spaces and hyphens for a clean check
        clean_value = self.value.replace("-", "").replace(" ", "").upper()
        
        # Basic check: usually starts with a letter, followed by 10 digits
        if not re.match(r"^[A-Z]\d{10}$", clean_value):
            raise ValueError("Must be a valid Philippine driver's license format.")
            
        # Optional: Save the cleanly formatted version back to the value
        object.__setattr__(self, 'value', clean_value)

@dataclass
class VerificationProfile(Entity):
    user_id: str
    license_number: LicenseNumber
    id_image_url: str  # Link to where the uploaded image is stored
    
    status: KycStatus = field(default=KycStatus.PENDING, init=False)
    admin_notes: str = field(default="", init=False)

    # 🛡️ STATE TRANSITION INVARIANT
    def approve(self):
        if self.status == KycStatus.APPROVED:
            raise ValueError("Profile is already approved.")
        if self.status == KycStatus.REJECTED:
            raise ValueError("Cannot approve a rejected profile. User must reapply.")
        self.status = KycStatus.APPROVED

    def reject(self, reason: str):
        if not reason.strip():
            raise ValueError("A reason must be provided for rejection.")
        self.status = KycStatus.REJECTED
        self.admin_notes = reason