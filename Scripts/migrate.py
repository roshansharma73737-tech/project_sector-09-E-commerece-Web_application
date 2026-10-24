
import os, sys
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / "backend" / ".env")
conn = psycopg2.connect(os.environ["DATABASE_URL"])
cur = conn.cursor()

cur.execute("""CREATE TABLE IF NOT EXISTS schema_migrations (
                 filename   VARCHAR(255) PRIMARY KEY,
                 applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())""")
conn.commit()

cur.execute("SELECT filename FROM schema_migrations")
done = {r[0] for r in cur.fetchall()}

pending = sorted(p for p in (ROOT / "database" / "migrations").glob("*.sql") if p.name not in done)
if not pending:
    print("Database is up to date.")
for f in pending:
    try:
        cur.execute(f.read_text(encoding="utf-8"))           # run the change
        cur.execute("INSERT INTO schema_migrations (filename) VALUES (%s)", (f.name,))
        conn.commit()                                         # all-or-nothing per file
        print("Applied:", f.name)
    except Exception as e:
        conn.rollback()
        sys.exit(f"FAILED {f.name}: {e}")
conn.close()