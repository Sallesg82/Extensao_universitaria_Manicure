import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'DB', 'beautyflow.db'))


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    init_tables(conn)
    return conn


def init_tables(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            email TEXT DEFAULT '',
            avatar_initials TEXT NOT NULL,
            avatar_bg TEXT NOT NULL DEFAULT '#daeaf8',
            avatar_color TEXT NOT NULL DEFAULT '#1a5fab',
            notes TEXT DEFAULT '',
            status TEXT DEFAULT 'regular',
            created_at TEXT DEFAULT (datetime('now', 'localtime')),
            updated_at TEXT DEFAULT (datetime('now', 'localtime'))
        );

        CREATE TABLE IF NOT EXISTS appointments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id INTEGER NOT NULL,
            service TEXT NOT NULL,
            appointment_date TEXT NOT NULL,
            appointment_time TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            price REAL NOT NULL DEFAULT 0,
            duration INTEGER DEFAULT 60,
            notes TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now', 'localtime')),
            updated_at TEXT DEFAULT (datetime('now', 'localtime')),
            FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS services (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            duration INTEGER NOT NULL DEFAULT 60,
            price REAL NOT NULL DEFAULT 0,
            color TEXT DEFAULT '#4a90d9',
            created_at TEXT DEFAULT (datetime('now', 'localtime'))
        );

        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL CHECK(type IN ('income','expense')),
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT DEFAULT '',
            payment_method TEXT DEFAULT '',
            date TEXT NOT NULL,
            appointment_id INTEGER,
            created_at TEXT DEFAULT (datetime('now', 'localtime')),
            FOREIGN KEY (appointment_id) REFERENCES appointments(id) ON DELETE SET NULL
        );
    """)
    conn.commit()


def seed_if_empty(conn):
    count = conn.execute("SELECT COUNT(*) as c FROM clients").fetchone()['c']
    if count > 0:
        return

    clients = [
        ('Ana Paula Silva', '(11) 98765-4321', 'ana@email.com', 'AP', '#daeaf8', '#1a5fab', 'frequente', '2024-01-15'),
        ('Carla Mendes', '(11) 97654-3210', 'carla@email.com', 'CM', '#f0e8f8', '#6a2e8a', 'regular', '2024-03-10'),
        ('Fernanda Costa', '(11) 96543-2109', 'fernanda@email.com', 'FC', '#e8f8ee', '#2e8a5a', 'regular', '2024-05-20'),
        ('Juliana Rocha', '(11) 95432-1098', 'juliana@email.com', 'JR', '#fdf3dc', '#8c5e10', 'regular', '2024-06-05'),
        ('Mariana Torres', '(11) 94321-0987', 'mariana@email.com', 'MT', '#fce8e8', '#8a2e2e', 'novo', '2025-02-01'),
        ('Patricia Lima', '(11) 93210-9876', 'patricia@email.com', 'PL', '#e8f0fc', '#2e5e8a', 'novo', '2026-04-01'),
        ('Rafaela Nunes', '(11) 92109-8765', 'rafaela@email.com', 'RN', '#f0f8e8', '#4a8a2e', 'frequente', '2023-11-10'),
        ('Beatriz Neves', '(11) 91098-7654', 'beatriz@email.com', 'BN', '#f8e8f4', '#8a2e6e', 'frequente', '2023-12-05'),
        ('Lúcia Ferreira', '(11) 90987-6543', 'lucia@email.com', 'LF', '#e8fcf8', '#2e8a7a', 'novo', '2026-04-15'),
    ]
    conn.executemany(
        "INSERT INTO clients (name, phone, email, avatar_initials, avatar_bg, avatar_color, status, created_at) VALUES (?,?,?,?,?,?,?,?)",
        clients
    )

    services = [
        ('Manicure Simples', 40, 35, '#4a90d9'),
        ('Pedicure Simples', 50, 40, '#2563a8'),
        ('Manicure + Pedicure', 80, 70, '#4a90d9'),
        ('Unhas em Gel', 90, 90, '#3a7abf'),
        ('Alongamento de Unhas', 120, 120, '#1a5fab'),
        ('Blindagem de Unhas', 60, 65, '#0f2340'),
        ('Design de Sobrancelha', 30, 45, '#8aaccb'),
        ('Sobrancelha + Manicure', 70, 80, '#4e8f6a'),
    ]
    conn.executemany(
        "INSERT INTO services (name, duration, price, color) VALUES (?,?,?,?)",
        services
    )

    appointments = [
        (1, 'Manicure + Pedicure', '2026-05-01', '08:30', 'done', 70, 80),
        (2, 'Design de Sobrancelha', '2026-05-01', '09:45', 'done', 45, 30),
        (3, 'Unhas em Gel', '2026-05-01', '11:00', 'confirmed', 90, 90),
        (4, 'Sobrancelha + Manicure', '2026-05-01', '13:30', 'pending', 80, 70),
        (5, 'Blindagem de Unhas', '2026-05-01', '15:00', 'pending', 65, 60),
        (6, 'Manicure Simples', '2026-05-01', '16:15', 'pending', 35, 40),
        (7, 'Alongamento de Unhas', '2026-05-01', '17:30', 'confirmed', 120, 120),
        (1, 'Unhas em Gel', '2026-04-17', '10:00', 'done', 90, 90),
        (2, 'Sobrancelha + Manicure', '2026-04-18', '14:00', 'done', 80, 70),
        (3, 'Unhas em Gel', '2026-04-15', '09:00', 'done', 90, 90),
        (4, 'Sobrancelha + Manicure', '2026-04-14', '11:00', 'done', 80, 70),
        (5, 'Blindagem de Unhas', '2026-04-10', '15:00', 'done', 65, 60),
        (7, 'Alongamento de Unhas', '2026-04-17', '10:00', 'done', 120, 120),
        (8, 'Manicure + Pedicure', '2026-04-29', '09:00', 'done', 70, 80),
        (9, 'Unhas em Gel', '2026-04-25', '14:00', 'done', 90, 90),
    ]
    conn.executemany(
        "INSERT INTO appointments (client_id, service, appointment_date, appointment_time, status, price, duration) VALUES (?,?,?,?,?,?,?)",
        appointments
    )

    transactions = [
        ('income', 'Ana Paula Silva — Manicure+Ped', 70, 'Manicure', 'Pix', '2026-05-01', 1),
        ('income', 'Carla Mendes — Sobrancelha', 45, 'Sobrancelha', 'Pix', '2026-05-01', 2),
        ('expense', 'Compra esmaltes e materiais', 180, 'Materiais', 'Débito', '2026-04-30', None),
        ('income', 'Rafaela Nunes — Alongamento', 120, 'Alongamento', 'Pix', '2026-04-30', 7),
        ('expense', 'Aluguel da sala (maio)', 650, 'Aluguel', 'TED', '2026-05-01', None),
    ]
    conn.executemany(
        "INSERT INTO transactions (type, description, amount, category, payment_method, date, appointment_id) VALUES (?,?,?,?,?,?,?)",
        transactions
    )

    conn.commit()
