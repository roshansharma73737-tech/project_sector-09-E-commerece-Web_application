
import os, sys, random
from datetime import datetime, timedelta
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / "backend" / ".env")
DATABASE_URL = os.getenv("DATABASE_URL")
HORIZON_DAYS = int(os.getenv("CATALOG_HORIZON_DAYS", "14"))
if not DATABASE_URL:
    sys.exit("DATABASE_URL missing. Create backend/.env first.")

conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

# safety guard: never wipe real users by accident
cur.execute("SELECT to_regclass('public.users') IS NOT NULL")
if cur.fetchone()[0]:
    cur.execute("SELECT COUNT(*) FROM users")
    existing = cur.fetchone()[0]
    if existing and "--force" not in sys.argv:
        sys.exit(f"STOPPED: {existing} user(s) exist. Re-running would DELETE them and all bookings.\n"
                 "Use scripts/migrate.py for changes. If you really mean it: --force")

print("Creating tables...")
cur.execute((ROOT / "database" / "schema.sql").read_text(encoding="utf-8"))
cur.execute((ROOT / "database" / "seed.sql").read_text(encoding="utf-8"))

print(f"Creating upcoming catalog ({HORIZON_DAYS} days ahead)...")
today = datetime.now(catalog.IST).date()
n = catalog.insert_services(cur, catalog.build_services(today, today + timedelta(days=HORIZON_DAYS - 1), random.Random()))
conn.commit()

print(f"  services created: {n}")
for t in ["users", "services", "seats", "bookings"]:
    cur.execute(f"SELECT COUNT(*) FROM {t}")
    print(f"  {t:10s}{cur.fetchone()[0]}")
print("\nNext: python scripts/create_admin.py   (then start the backend)")
conn.close()