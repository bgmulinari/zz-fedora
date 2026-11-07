#!/usr/bin/python3
"""An opencode database in the newer session_message store: a prompt typed
just before midnight and answered after it, and a reply to a user row opencode
wrote itself."""
import json, sqlite3, sys, time
from datetime import date, datetime, timedelta

now = int(time.time() * 1000)
late = int(datetime.combine(date.today() - timedelta(days=1), datetime.min.time()).replace(hour=23, minute=59).timestamp() * 1000)
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE session_message (id text PRIMARY KEY, session_id text, type text, seq integer, time_created integer, data text)")
tokens = {"input": 100, "output": 50, "reasoning": 0, "cache": {"read": 0, "write": 0}}
model = {"providerID": "opencode-go", "id": "glm-5"}
rows = [
    ("u-late", "late", "user", 1, late, {"time": {"created": late}}),
    ("a-late", "late", "assistant", 2, now, {"time": {"created": now}, "model": model, "tokens": tokens}),
    ("u-auto", "auto", "user", 1, now, {"time": {"created": now}, "synthetic": True}),
    ("a-auto", "auto", "assistant", 2, now, {"time": {"created": now}, "model": model, "tokens": tokens}),
]
for row_id, session, kind, seq, created, data in rows:
    conn.execute("INSERT INTO session_message VALUES (?, ?, ?, ?, ?, ?)", (row_id, session, kind, seq, created, json.dumps(data)))
conn.commit()
