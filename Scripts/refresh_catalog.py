
import os, sys, random
from datetime import datetime, timedelta
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog

load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")
HORIZON = int(os.getenv("CATALOG_HORIZON_DAYS", "14"))
PENDING_MIN = int(os.getenv("PENDING_BOOKING_MINUTES", "30"))

conn = psycopg2.connect(os.environ["DATABASE_URL"]); cur = conn.cursor()

cur.execute("UPDATE bookings SET status='expired' WHERE status='pending' AND created_at < NOW() - make_interval(mins => %s)", (PENDING_MIN,))
print("pending bookings expired:", cur.rowcount)
cur.execute("UPDATE seats SET status='available', held_by=NULL, held_until=NULL WHERE status='held' AND held_until < NOW()")
print("held seats released:     ", cur.rowcount)
cur.execute("UPDATE services SET is_active=FALSE WHERE is_active AND start_time < NOW()")
print("past services hidden:    ", cur.rowcount)
cur.execute("""UPDATE services s SET available_seats = (SELECT COUNT(*) FROM seats WHERE service_id=s.id AND status='available')
               WHERE s.is_active AND s.available_seats <> (SELECT COUNT(*) FROM seats WHERE service_id=s.id AND status='available')""")
print("seat counters fixed:     ", cur.rowcount)

today = datetime.now(catalog.IST).date()
cur.execute("SELECT MAX(start_time) FROM services WHERE source='dummy'")
last = cur.fetchone()[0]
first_new = (last.astimezone(catalog.IST).date() + timedelta(days=1)) if last else today
last_new = today + timedelta(days=HORIZON - 1)
if first_new > last_new:
    print("catalog already covers the next", HORIZON, "days")
else:
    n = catalog.insert_services(cur, catalog.build_services(first_new, last_new, random.Random()))
    print(f"new services added for {first_new} .. {last_new}: {n}")
conn.commit(); conn.close()