import sqlite3
import uuid
from datetime import datetime, timedelta

def init_database():
    # Connect to local SQLite DB (creates file if it doesn't exist)
    conn = sqlite3.connect('sabaygo.db')
    cursor = conn.cursor()

    # Enable Foreign Key Support in SQLite
    cursor.execute("PRAGMA foreign_keys = ON;")

    print("Creating SabayGo Schema...")
        # --- SCHEMA DEFINITION (3NF) ---
    schema = """
    CREATE TABLE IF NOT EXISTS tbl_users (
        user_id VARCHAR(36) PRIMARY KEY,
        role_type VARCHAR(20) NOT NULL,
        first_name VARCHAR(50) NOT NULL,
        last_name VARCHAR(50) NOT NULL,
        middle_name VARCHAR(50),
        email VARCHAR(100) NOT NULL UNIQUE,
        phone_number VARCHAR(15) NOT NULL UNIQUE,
        dob DATE NOT NULL,
        ekyc_status VARCHAR(20) DEFAULT 'Pending',
        trust_score DECIMAL(3,2) DEFAULT 5.00
    );

    CREATE TABLE IF NOT EXISTS tbl_emergency_contacts (
        contact_id VARCHAR(36) PRIMARY KEY,
        user_id VARCHAR(36) NOT NULL,
        contact_name VARCHAR(100) NOT NULL,
        contact_phone VARCHAR(15) NOT NULL,
        FOREIGN KEY(user_id) REFERENCES tbl_users(user_id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS tbl_subscriptions (
        subscription_id VARCHAR(36) PRIMARY KEY,
        user_id VARCHAR(36) NOT NULL,
        plan_type VARCHAR(50) NOT NULL,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        status VARCHAR(20) DEFAULT 'Active',
        FOREIGN KEY(user_id) REFERENCES tbl_users(user_id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS tbl_vehicles (
        vehicle_id VARCHAR(36) PRIMARY KEY,
        driver_id VARCHAR(36) NOT NULL,
        plate_number VARCHAR(15) NOT NULL UNIQUE,
        model VARCHAR(50) NOT NULL,
        color VARCHAR(30) NOT NULL,
        FOREIGN KEY(driver_id) REFERENCES tbl_users(user_id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS tbl_nodes (
        node_id VARCHAR(36) PRIMARY KEY,
        node_name VARCHAR(100) NOT NULL,
        latitude DECIMAL(11,8) NOT NULL,
        longitude DECIMAL(11,8) NOT NULL,
        is_active BOOLEAN DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS tbl_ride_offers (
        offer_id VARCHAR(36) PRIMARY KEY,
        driver_id VARCHAR(36) NOT NULL,
        start_node_id VARCHAR(36) NOT NULL,
        end_node_id VARCHAR(36) NOT NULL,
        departure_time DATETIME NOT NULL,
        available_seats INT DEFAULT 3,
        status VARCHAR(20) DEFAULT 'Active',
        FOREIGN KEY(driver_id) REFERENCES tbl_users(user_id) ON DELETE CASCADE,
        FOREIGN KEY(start_node_id) REFERENCES tbl_nodes(node_id),
        FOREIGN KEY(end_node_id) REFERENCES tbl_nodes(node_id)
    );

    CREATE TABLE IF NOT EXISTS tbl_trips (
        trip_id VARCHAR(36) PRIMARY KEY,
        offer_id VARCHAR(36) NOT NULL,
        passenger_id VARCHAR(36) NOT NULL,
        pickup_node_id VARCHAR(36) NOT NULL,
        dropoff_node_id VARCHAR(36) NOT NULL,
        shared_cost DECIMAL(10,2) NOT NULL,
        status VARCHAR(20) DEFAULT 'Matched',
        FOREIGN KEY(offer_id) REFERENCES tbl_ride_offers(offer_id) ON DELETE CASCADE,
        FOREIGN KEY(passenger_id) REFERENCES tbl_users(user_id) ON DELETE CASCADE,
        FOREIGN KEY(pickup_node_id) REFERENCES tbl_nodes(node_id),
        FOREIGN KEY(dropoff_node_id) REFERENCES tbl_nodes(node_id)
    );
    """
    cursor.executescript(schema)
    print("Schema Built Successfully.")

    # --- SEEDING DUMMY DATA ---
    print("Populating Dummy Data...")

    # Generate fixed UUIDs so data is consistent when querying
    driver_id = str(uuid.uuid4())
    commuter_id = str(uuid.uuid4())
    node_matina = str(uuid.uuid4())
    node_bangkal = str(uuid.uuid4())
    node_ulas = str(uuid.uuid4())
    offer_id = str(uuid.uuid4())

    # 1. Insert Users (1 Driver, 1 Commuter)
    cursor.execute("""
        INSERT INTO tbl_users (user_id, role_type, first_name, last_name, email, phone_number, dob, ekyc_status) 
        VALUES (?, 'Driver', 'Carl', 'Fernandez', 'carl.f@umindanao.edu.ph', '+639123456789', '2002-05-14', 'Verified')
    """, (driver_id,))
    
    cursor.execute("""
        INSERT INTO tbl_users (user_id, role_type, first_name, last_name, email, phone_number, dob, ekyc_status) 
        VALUES (?, 'Passenger', 'Sarah', 'K.', 'sarah.k@umindanao.edu.ph', '+639987654321', '2004-11-22', 'Verified')
    """, (commuter_id,))

    # 2. Insert Subscription for Commuter
    cursor.execute("""
        INSERT INTO tbl_subscriptions (subscription_id, user_id, plan_type, start_date, end_date)
        VALUES (?, ?, 'Student Flat-Rate', date('now'), date('now', '+30 days'))
    """, (str(uuid.uuid4()), commuter_id))

    # 3. Insert Vehicle for Driver
    cursor.execute("""
        INSERT INTO tbl_vehicles (vehicle_id, driver_id, plate_number, model, color)
        VALUES (?, ?, 'DVO-1234', 'Toyota Vios', 'Silver')
    """, (str(uuid.uuid4()), driver_id))

    # 4. Insert Highway Nodes (McArthur Highway Coordinates)
    nodes = [
        (node_matina, 'UM Matina Gate', 7.065833, 125.596111),
        (node_bangkal, 'Bangkal Center', 7.054444, 125.580278),
        (node_ulas, 'Ulas Junction Hub', 7.042500, 125.558333)
    ]
    cursor.executemany("INSERT INTO tbl_nodes (node_id, node_name, latitude, longitude) VALUES (?, ?, ?, ?)", nodes)

    # 5. Insert Ride Offer (Driver traveling from Matina to Ulas)
    departure = (datetime.now() + timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S')
    cursor.execute("""
        INSERT INTO tbl_ride_offers (offer_id, driver_id, start_node_id, end_node_id, departure_time, available_seats)
        VALUES (?, ?, ?, ?, ?, 2)
    """, (offer_id, driver_id, node_matina, node_ulas, departure))

    # 6. Insert Matched Trip (Commuter booked Matina to Ulas)
    # Notice the explicit 17.00 shared_cost mimicking the screen prototype
    cursor.execute("""
        INSERT INTO tbl_trips (trip_id, offer_id, passenger_id, pickup_node_id, dropoff_node_id, shared_cost)
        VALUES (?, ?, ?, ?, ?, 17.00)
    """, (str(uuid.uuid4()), offer_id, commuter_id, node_matina, node_ulas))

    conn.commit()
    conn.close()
    print("Database Initialization Complete! 'sabaygo.db' is ready for defense.")

if __name__ == '__main__':
    init_database()