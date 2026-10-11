"""Vectors for tests/selfhost/fixtures/link/db_migrate (L113, D2680).

Prints the FNV-1a 64 checksum (as the signed i64 the journal stores) of each
migration's `up` text, and replays the fixture's happy path against Python's
sqlite3 so the expected table state the fixture asserts is an independent
oracle: users has 2 rows, the index exists after up, and is gone after down 1.
"""
import sqlite3

UPS = [
    'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    "INSERT INTO users (id, name) VALUES (1, 'ada'), (2, 'bob')",
    'CREATE INDEX users_name ON users (name)',
]
DOWNS = ['DROP TABLE users', 'DELETE FROM users', 'DROP INDEX users_name']


def fnv1a64(text):
    h = 14695981039346656037
    for b in text.encode():
        h = ((h ^ b) * 1099511628211) & (2**64 - 1)
    return h - 2**64 if h >= 2**63 else h


def main():
    for i, up in enumerate(UPS, 1):
        print('checksum', i, fnv1a64(up))
    db = sqlite3.connect(':memory:')
    for up in UPS:
        db.executescript(up)
    print('users', db.execute('SELECT count(*) FROM users').fetchone()[0])
    print('index', db.execute("SELECT count(*) FROM sqlite_master WHERE name='users_name'").fetchone()[0])
    db.executescript(DOWNS[2])
    print('index after down', db.execute("SELECT count(*) FROM sqlite_master WHERE name='users_name'").fetchone()[0])


if __name__ == '__main__':
    main()
