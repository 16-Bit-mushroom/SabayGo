-- Enable foreign key constraints (Required for SQLite)
PRAGMA foreign_keys = ON;

-- ==========================================
-- 1. INDEPENDENT TABLES (No Foreign Keys)
-- ==========================================

CREATE TABLE Terminals (
    TerminalID TEXT PRIMARY KEY,
    TerminalName TEXT NOT NULL,
    City TEXT NOT NULL,
    Latitude REAL NOT NULL,
    Longitude REAL NOT NULL,
    IsActive INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE Drivers (
    DriverID TEXT PRIMARY KEY,
    FullName TEXT NOT NULL,
    ContactNumber TEXT NOT NULL,
    CTTMOIDPhotoUrl TEXT NOT NULL,
    CTTMOIDNumber TEXT UNIQUE NOT NULL,
    LicenseNumber TEXT UNIQUE NOT NULL,
    LicenseExpiryDate TEXT NOT NULL,
    EmploymentStatus TEXT NOT NULL DEFAULT 'Active' 
        CHECK(EmploymentStatus IN ('Active', 'Suspended', 'On-Leave', 'Inactive'))
);

CREATE TABLE Vans (
    VanID TEXT PRIMARY KEY,
    PhotoFrontUrl TEXT NOT NULL,
    PhotoBackUrl TEXT NOT NULL,
    PhotoLeftUrl TEXT NOT NULL,
    PhotoRightUrl TEXT NOT NULL,
    PlateNumber TEXT UNIQUE NOT NULL,
    CPCCaseNo TEXT UNIQUE NOT NULL,
    CPCNumber TEXT UNIQUE NOT NULL,
    Brand TEXT NOT NULL,
    Model TEXT NOT NULL,
    Color TEXT NOT NULL,
    SeatCapacity INTEGER NOT NULL DEFAULT 14,
    OperationalStatus TEXT NOT NULL DEFAULT 'Active' 
        CHECK(OperationalStatus IN ('Active (Ready)', 'Maintenance', 'Inactive')),
    RegisteredRoute TEXT NOT NULL 
        CHECK(RegisteredRoute IN ('Ecoland-Cotabato', 'Ecoland-Tagum'))
);

CREATE TABLE Passengers (
    PassengerID TEXT PRIMARY KEY,
    FirstName TEXT NOT NULL,
    MiddleName TEXT,
    LastName TEXT NOT NULL,
    Email TEXT UNIQUE NOT NULL,
    PhoneNumber TEXT UNIQUE NOT NULL,
    HomeAddress TEXT,
    Gender TEXT CHECK(Gender IN ('Male', 'Female', 'Other', 'Prefer not to say')),
    EmergContactName TEXT,
    EmergContactRelation TEXT,
    EmergContactNumber TEXT,
    TrustRating REAL DEFAULT 5.0
);

-- ==========================================
-- 2. DEPENDENT TABLES (Level 1)
-- ==========================================

CREATE TABLE Conductors (
    ConductorID TEXT PRIMARY KEY,
    FirstName TEXT NOT NULL,
    MiddleName TEXT,
    LastName TEXT NOT NULL,
    BirthDate TEXT NOT NULL,
    PhoneNumber TEXT UNIQUE NOT NULL,
    Gender TEXT NOT NULL CHECK(Gender IN ('Male', 'Female', 'Other', 'Prefer not to say')),
    HomeAddress TEXT NOT NULL,
    ProfilePicUrl TEXT,
    AssignedTerminalID TEXT NOT NULL,
    EmploymentStatus TEXT NOT NULL DEFAULT 'Active' CHECK(EmploymentStatus IN ('Active', 'Suspended', 'Inactive')),
    FOREIGN KEY (AssignedTerminalID) REFERENCES Terminals(TerminalID)
);

CREATE TABLE PassengersSettings (
    PassengersID TEXT PRIMARY KEY,
    PushEnabled INTEGER NOT NULL DEFAULT 1,
    TailoredSchedules INTEGER NOT NULL DEFAULT 1,
    TripUpdates INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (PassengersID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE SavedDestinations (
    DestinationID TEXT PRIMARY KEY,
    PassengerID TEXT NOT NULL,
    Label TEXT NOT NULL,
    Address TEXT NOT NULL,
    Latitude REAL NOT NULL,
    Longitude REAL NOT NULL,
    CreatedAt TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE Notifications (
    NotificationID TEXT PRIMARY KEY,
    PassengerID TEXT NOT NULL,
    Title TEXT NOT NULL,
    Message TEXT NOT NULL,
    Type TEXT NOT NULL CHECK(Type IN ('Tailored Schedule', 'Trip Update', 'System Alert')),
    IsRead INTEGER NOT NULL DEFAULT 0,
    CreatedAt TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE LogBookEntries (
    LogEntryID TEXT PRIMARY KEY,
    PassengerName TEXT NOT NULL,
    PhoneNumber TEXT NOT NULL,
    Address TEXT NOT NULL,
    AssignedVanID TEXT NOT NULL,
    DestinationCity TEXT NOT NULL,
    LogTimestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (AssignedVanID) REFERENCES Vans(VanID)
);

-- ==========================================
-- 3. HIGHLY RELATIONAL TABLES (Level 2)
-- ==========================================

CREATE TABLE TripSchedules (
    ScheduleID TEXT PRIMARY KEY,
    OriginTerminalID TEXT NOT NULL,
    DestTerminalID TEXT NOT NULL,
    AssignedVanID TEXT NOT NULL,
    AssignedDriverID TEXT NOT NULL,
    ConductorID TEXT,
    DepartureDateTime TEXT NOT NULL,
    StandardFare REAL NOT NULL,
    FOREIGN KEY (OriginTerminalID) REFERENCES Terminals(TerminalID),
    FOREIGN KEY (DestTerminalID) REFERENCES Terminals(TerminalID),
    FOREIGN KEY (AssignedVanID) REFERENCES Vans(VanID),
    FOREIGN KEY (AssignedDriverID) REFERENCES Drivers(DriverID),
    FOREIGN KEY (ConductorID) REFERENCES Conductors(ConductorID)
);

-- ==========================================
-- 4. TRANSACTION & AUDIT TABLES (Level 3)
-- ==========================================

CREATE TABLE Bookings (
    BookingID TEXT PRIMARY KEY,
    TicketNumber TEXT UNIQUE NOT NULL,
    PassengerID TEXT NOT NULL,
    TripID TEXT NOT NULL,
    BookingType TEXT NOT NULL CHECK(BookingType IN ('App', 'Walk-in')),
    FareAmount REAL NOT NULL,
    Status TEXT DEFAULT 'Pending' CHECK(Status IN ('Pending', 'Confirmed', 'Boarded', 'Cancelled')),
    BookedAt TEXT NOT NULL,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID),
    FOREIGN KEY (TripID) REFERENCES TripSchedules(ScheduleID)
);

CREATE TABLE PassengerTripHistory (
    HistoryID TEXT PRIMARY KEY,
    PassengerID TEXT NOT NULL,
    BookingID TEXT NOT NULL,
    Origin TEXT NOT NULL,
    Destination TEXT NOT NULL,
    FarePaid REAL NOT NULL,
    Status TEXT NOT NULL CHECK(Status IN ('Completed', 'Cancelled', 'No-Show')),
    CompletedAt TEXT NOT NULL,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID),
    FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
);

CREATE TABLE Yolov8_audit_logs (
    AuditID TEXT PRIMARY KEY,
    ScheduleID TEXT NOT NULL,
    DriverID TEXT NOT NULL,
    CapturedAt TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    BookedCount INTEGER NOT NULL,
    VisualCount INTEGER NOT NULL,
    Variance INTEGER NOT NULL,
    SnapshotURL TEXT NOT NULL,
    ResolutionStatus TEXT NOT NULL DEFAULT 'Pending' 
        CHECK(ResolutionStatus IN ('Pending', 'Cash_Logged', 'Ignored')),
    FOREIGN KEY (ScheduleID) REFERENCES TripSchedules(ScheduleID),
    FOREIGN KEY (DriverID) REFERENCES Drivers(DriverID)
);