-- Enable foreign key constraints (Required for SQLite)
PRAGMA foreign_keys = ON;

-- ==========================================
-- 1. INDEPENDENT TABLES (No Foreign Keys)
-- ==========================================

CREATE TABLE Passengers (
    PassengerID TEXT PRIMARY KEY,
    FullName TEXT,
    Email TEXT UNIQUE,
    PasswordHash TEXT,
    PhoneNumber TEXT,
    Address TEXT,
    Gender TEXT,
    EmergencyContactName TEXT,
    EmergencyContactPhone TEXT,
    TrustRating REAL,
    AvatarUrl TEXT,
    CreatedAt TEXT
);

CREATE TABLE Terminals (
    TerminalID INTEGER PRIMARY KEY AUTOINCREMENT,
    TerminalName TEXT,
    LocationAddress TEXT,
    Latitude REAL,
    Longitude REAL,
    IsActive INTEGER
);

CREATE TABLE Drivers (
    DriverID INTEGER PRIMARY KEY AUTOINCREMENT,
    FullName TEXT,
    ContactNumber TEXT,
    CTTMOIDPhotoUrl TEXT,
    CTTMOIDNumber TEXT,
    LicenseNumber TEXT,
    LicenseExpiryDate TEXT,
    EmploymentStatus TEXT
);

CREATE TABLE Vans (
    VanID INTEGER PRIMARY KEY AUTOINCREMENT,
    PhotoFrontUrl TEXT,
    PhotoBackUrl TEXT,
    PhotoLeftUrl TEXT,
    PhotoRightUrl TEXT,
    PlateNumber TEXT UNIQUE,
    CPCCaseNo TEXT,
    CPCNumber TEXT,
    Brand TEXT,
    Model TEXT,
    Color TEXT,
    SeatCapacity INTEGER,
    OperationalStatus TEXT,
    RegisteredRoute TEXT
);

-- ==========================================
-- 2. DEPENDENT TABLES (Level 1 - Links to Independent Tables)
-- ==========================================

CREATE TABLE PassengerSettings (
    SettingsID INTEGER PRIMARY KEY AUTOINCREMENT,
    PassengerID TEXT,
    PushEnabled INTEGER,
    TailoredSchedules INTEGER,
    TripUpdates INTEGER,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE SavedDestinations (
    DestinationID INTEGER PRIMARY KEY AUTOINCREMENT,
    PassengerID TEXT,
    Label TEXT,
    Address TEXT,
    Latitude REAL,
    Longitude REAL,
    CreatedAt TEXT,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE Notifications (
    NotificationID INTEGER PRIMARY KEY AUTOINCREMENT,
    PassengerID TEXT,
    Title TEXT,
    Message TEXT,
    Type TEXT,
    IsRead INTEGER DEFAULT 0,
    CreatedAt TEXT,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID) ON DELETE CASCADE
);

CREATE TABLE TerminalStaff (
    StaffID TEXT PRIMARY KEY,
    TerminalID INTEGER,
    FullName TEXT,
    Email TEXT UNIQUE,
    PasswordHash TEXT,
    SystemRole TEXT,
    CooperativeName TEXT,
    AccountStatus TEXT,
    CreatedAt TEXT,
    FOREIGN KEY (TerminalID) REFERENCES Terminals(TerminalID)
);

CREATE TABLE Conductors (
    ConductorID INTEGER PRIMARY KEY AUTOINCREMENT,
    FullName TEXT,
    PhoneNumber TEXT,
    AssignedVanID INTEGER,
    Status TEXT,
    FOREIGN KEY (AssignedVanID) REFERENCES Vans(VanID)
);

CREATE TABLE LogBookEntries (
    LogEntryID INTEGER PRIMARY KEY AUTOINCREMENT,
    PassengerName TEXT,
    PhoneNumber TEXT,
    Address TEXT,
    AssignedVanID INTEGER,
    DestinationCity TEXT,
    LogTimestamp TEXT,
    FOREIGN KEY (AssignedVanID) REFERENCES Vans(VanID)
);

-- ==========================================
-- 3. HIGHLY RELATIONAL TABLES (Level 2 - Links to Level 1)
-- ==========================================

CREATE TABLE TripSchedules (
    ScheduleID INTEGER PRIMARY KEY AUTOINCREMENT,
    OriginTerminalID INTEGER,
    DestTerminalID INTEGER,
    AssignedVanID INTEGER,
    AssignedDriverID INTEGER,
    ConductorID INTEGER,
    DepartureDateTime TEXT,
    StandardFare REAL,
    FOREIGN KEY (OriginTerminalID) REFERENCES Terminals(TerminalID),
    FOREIGN KEY (DestTerminalID) REFERENCES Terminals(TerminalID),
    FOREIGN KEY (AssignedVanID) REFERENCES Vans(VanID),
    FOREIGN KEY (AssignedDriverID) REFERENCES Drivers(DriverID),
    FOREIGN KEY (ConductorID) REFERENCES Conductors(ConductorID)
);

-- ==========================================
-- 4. TRANSACTION TABLES (Level 3 - Links to Level 2)
-- ==========================================

CREATE TABLE Bookings (
    BookingID INTEGER PRIMARY KEY AUTOINCREMENT,
    TicketNumber TEXT UNIQUE,
    PassengerID TEXT,
    TripID INTEGER,
    BookingType TEXT,
    Status TEXT,
    BookedAt TEXT,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID),
    FOREIGN KEY (TripID) REFERENCES TripSchedules(ScheduleID)
);

CREATE TABLE PassengerTripHistory (
    HistoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    PassengerID TEXT,
    BookingID INTEGER,
    Origin TEXT,
    Destination TEXT,
    FarePaid REAL,
    Status TEXT,
    CompletedAt TEXT,
    FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID),
    FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
);