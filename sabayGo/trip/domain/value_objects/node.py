from dataclasses import dataclass, field

@dataclass(frozen=True)
class Node:
    name: str
    latitude: float
    longitude: float

    def __post_init__(self):
        # Geographic Invariants
        if not (-90.0 <= self.latitude <= 90.0):
            raise ValueError(f"Invalid latitude: {self.latitude}. Must be between -90 and 90.")
        
        if not (-180.0 <= self.longitude <= 180.0):
            raise ValueError(f"Invalid longitude: {self.longitude}. Must be between -180 and 180.")
            
        if not self.name.strip():
            raise ValueError("Node name cannot be empty.")