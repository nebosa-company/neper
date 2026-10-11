"""Oracle for tests/selfhost/fixtures/link/db_orm (L112, D2681).

Replays the statements `e.db.orm` emits for the fixture's User/Post graph through
Python's sqlite3 and prints what the fixture asserts: the preload `IN (...) ORDER BY
user_id, id` row order (posts c1 c2 c3 for user 3, a1 a2 for user 1), the filtered
`age >= 0` select order, and that a repeated explicit key is a constraint error.
"""
import sqlite3

db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER NOT NULL, score REAL NOT NULL, active INTEGER NOT NULL)')
db.execute('CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, views INTEGER NOT NULL)')
for row in [('Ada Lé', 36, 0.1, 1), ('Bob', -7, 2.5, 0)]:
    db.execute('INSERT INTO users (name, age, score, active) VALUES (?, ?, ?, ?)', row)
db.execute('INSERT INTO users (id, name, age, score, active) VALUES (?, ?, ?, ?, ?)', (10, '', 41, 0.0, 1))
print('generated ids', [r[0] for r in db.execute('SELECT id FROM users ORDER BY id')])
try:
    db.execute('INSERT INTO users (id, name, age, score, active) VALUES (?, ?, ?, ?, ?)', (10, 'x', 1, 1.0, 0))
except sqlite3.IntegrityError as e:
    print('duplicate key:', type(e).__name__)
print('age>=0 order', [r[0] for r in db.execute('SELECT id FROM users WHERE age >= ? ORDER BY age DESC, id', (0,))])
for uid, title, views in [(3, 'c1', 5), (1, 'a1', 10), (3, 'c2', 0), (1, 'a2', 4000000000), (3, 'c3', 7)]:
    db.execute('INSERT INTO posts (user_id, title, views) VALUES (?, ?, ?)', (uid, title, views))
print('preload', [r[0] for r in db.execute('SELECT title FROM posts WHERE user_id IN (?, ?, ?) ORDER BY user_id, id', (3, 2, 1))])
