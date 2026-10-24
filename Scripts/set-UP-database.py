
import os, sys, random, itertools
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values, Json
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / "backend" / ".env")

DATABASE_URL    = os.getenv("DATABASE_URL")
HORIZON_DAYS    = int(os.getenv("CATALOG_HORIZON_DAYS", "14"))      # how many days ahead the catalog covers
PENDING_MINUTES = int(os.getenv("PENDING_BOOKING_MINUTES", "30"))   # abandoned bookings expire after this
MIGRATIONS_DIR  = ROOT / "database" / "migrations"
IST = timezone(timedelta(hours=5, minutes=30))


# ======================================================================
#  CATALOG CONTENT  - the dummy flights, trains, movies and events that
#  REAL users will search and book. EDIT THESE LISTS to change what the
#  website shows. (Users and bookings are never created here.)
# ======================================================================
MAIN_CITIES = ["Ahmedabad", "Delhi", "Mumbai", "Bengaluru", "Hyderabad"]
ALL_CITIES  = MAIN_CITIES + ["Chennai", "Pune", "Jaipur"]
ROUTES      = list(itertools.permutations(MAIN_CITIES, 2))           # 20 routes

TRANSPORT = {
    "flight": dict(providers=["IndiGo", "Air India", "Vistara", "SpiceJet", "Akasa Air"],
                   price=(2500, 9000), dur=(1.0, 3.0), per_day=2, hours=list(range(5, 23)),
                   categories=["economy", "business"]),
    "bus":    dict(providers=["RedBus Travels", "Orange Tours", "VRL", "Neeta"],
                   price=(400, 1800), dur=(5, 14), per_day=1, hours=[6, 18, 19, 20, 21, 22],
                   categories=["sleeper", "seater", "ac-sleeper"]),
    "train":  dict(providers=["Rajdhani", "Shatabdi", "Duronto", "Intercity"],
                   price=(350, 2500), dur=(4, 18), per_day=1, hours=[6, 9, 14, 17, 21, 22],
                   categories=["sleeper", "3AC", "2AC", "chair-car"]),
}
METRO_STATIONS = {
    "Ahmedabad": ["Vastral Gam", "Kankaria East", "Old High Court", "Apparel Park", "Thaltej"],
    "Delhi":     ["Rajiv Chowk", "Kashmere Gate", "Hauz Khas", "Dwarka Sec 21", "Noida City Centre"],
    "Mumbai":    ["Versova", "Andheri", "Ghatkopar", "Marol Naka", "Airport Road"],
    "Bengaluru": ["Majestic", "MG Road", "Indiranagar", "Yeshwanthpur", "Whitefield"],
    "Hyderabad": ["Miyapur", "Ameerpet", "Secunderabad", "HITEC City", "LB Nagar"],
}
MOVIES   = [("Galaxy Raiders", "action"), ("Love in Lisbon", "romance"), ("The Last Heist", "thriller"),
            ("Funny Business", "comedy"), ("Deep Blue", "drama"), ("Monsoon Tales", "drama"),
            ("Cyber Kings", "sci-fi"), ("Haunted Hostel", "horror")]
THEATRES = ["PVR Cinemas", "INOX", "Cinepolis", "Carnival"]
EVENTS   = [("Indie Music Night", "concert"), ("Tech Meetup", "conference"), ("Stand-up Comedy Show", "comedy"),
            ("Food Carnival", "festival"), ("Cricket Fan Fest", "sports"), ("Startup Summit", "conference"),
            ("Classical Evening", "concert"), ("Art & Craft Expo", "exhibition")]

SEAT_LAYOUT = {"flight": (10, "ABCDEF"), "bus": (10, "ABCD"), "train": (12, "ABCDE"),
               "metro": (8, "ABCDE"), "movie": (8, "ABCDEF"), "event": (10, "ABCDEF")}


def _at(day, hour, minute=0):
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=IST)


def build_services(first_day, last_day, rng):
    """Every service for each day first_day..last_day. Times that already passed are skipped."""
    now, out = datetime.now(IST), []
    day = first_day
    while day <= last_day:
        for kind, cfg in TRANSPORT.items():                       # flights / buses / trains, every route
            for o, d in ROUTES:
                route_rng = random.Random(f"{kind}-{o}-{d}")      # same route = similar price every day
                base, dur = route_rng.uniform(*cfg["price"]), route_rng.uniform(*cfg["dur"])
                for hour in rng.sample(cfg["hours"], cfg["per_day"]):
                    start = _at(day, hour, rng.choice([0, 15, 30, 45]))
                    if start <= now:
                        continue
                    prov, cat = rng.choice(cfg["providers"]), rng.choice(cfg["categories"])
                    price = base * rng.uniform(0.9, 1.15) * (1.8 if cat == "business" else 1.0)
                    out.append((kind, f"{prov} {rng.randint(100, 999)}", prov, o, d, None, cat, start,
                                start + timedelta(hours=dur), max(round(price, -1), 10),
                                round(rng.uniform(3.2, 4.9), 1), {"duration_hours": round(dur, 1)}))
        for city in MAIN_CITIES:                                  # metro: 3 trips per city per day
            for hour in rng.sample(range(6, 22), 3):
                start = _at(day, hour, rng.choice([0, 20, 40]))
                if start <= now:
                    continue
                a, b = rng.sample(METRO_STATIONS[city], 2)
                out.append(("metro", f"{city} Metro", f"{city} Metro", a, b, city, "standard", start,
                            start + timedelta(minutes=rng.randint(15, 50)), float(rng.choice([20, 30, 40, 50, 60])),
                            round(rng.uniform(3.5, 4.8), 1), {}))
        for city in MAIN_CITIES:                                  # movies: 3 shows per city per day
            for hour in rng.sample([10, 13, 16, 19, 22], 3):
                start = _at(day, hour)
                if start <= now:
                    continue
                t, g = rng.choice(MOVIES)
                out.append(("movie", t, rng.choice(THEATRES), None, None, city, g, start,
                            start + timedelta(hours=2.5), round(rng.uniform(150, 500), -1),
                            round(rng.uniform(3.0, 4.8), 1), {"language": rng.choice(["Hindi", "English", "Gujarati"])}))
        t, c = rng.choice(EVENTS)                                 # events: 1 per day, random city
        city = rng.choice(ALL_CITIES)
        start = _at(day, rng.choice([17, 18, 19, 20]))
        if start > now:
            out.append(("event", f"{t} {city}", "City Events Co.", None, None, city, c, start,
                        start + timedelta(hours=4), round(rng.uniform(200, 3000), -1),
                        round(rng.uniform(3.5, 4.9), 1),
                        {"venue": rng.choice(["Grand Hall", "Open Arena", "Convention Centre"])}))
        day += timedelta(days=1)
    return out


def insert_services(cur, services):
    """Insert services and one seat row per seat."""
    for s in services:
        rows, cols = SEAT_LAYOUT[s[0]]
        total = rows * len(cols)
        cur.execute(
            """INSERT INTO services (type,title,provider,origin,destination,city,category,start_time,end_time,
                                     base_price,total_seats,available_seats,rating,details,source)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'dummy') RETURNING id""",
            (*s[:10], total, total, s[10], Json(s[11])))
        sid = cur.fetchone()[0]
        seats = [(sid, f"{r}{c}", "premium" if r <= 2 else "standard", 1.5 if r <= 2 else 1.0)
                 for r in range(1, rows + 1) for c in cols]       # first 2 rows cost 1.5x
        execute_values(cur, "INSERT INTO seats (service_id, seat_no, seat_class, price_factor) VALUES %s", seats)
    return len(services)


# ======================================================================
#  JOB 1: FIRST BUILD
# ======================================================================
def table_exists(cur, name):
    cur.execute("SELECT to_regclass(%s) IS NOT NULL", (f"public.{name}",))
    return cur.fetchone()[0]


def ensure_migrations_table(cur):
    cur.execute("""CREATE TABLE IF NOT EXISTS schema_migrations (
                     filename   VARCHAR(255) PRIMARY KEY,
                     applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())""")


def first_build(cur, force):
    # safety guard: this job DROPS every table, so never run it over real users by accident
    if table_exists(cur, "users"):
        cur.execute("SELECT COUNT(*) FROM users")
        users = cur.fetchone()[0]
        if users and not force:
            sys.exit(f"STOPPED: {users} user(s) exist. A first build would DELETE them and all bookings.\n"
                     "Use --migrate for database changes. If you really mean it: --force")

    print("Creating tables and views...")
    cur.execute((ROOT / "database" / "schema.sql").read_text(encoding="utf-8"))
    cur.execute((ROOT / "database" / "seed.sql").read_text(encoding="utf-8"))

    # schema.sql is the complete current structure, so every migration file that exists
    # right now is already included in it. Mark them done; only NEW files will run later.
    cur.execute("DROP TABLE IF EXISTS schema_migrations")
    ensure_migrations_table(cur)
    existing = sorted(p.name for p in MIGRATIONS_DIR.glob("*.sql"))
    if existing:
        execute_values(cur, "INSERT INTO schema_migrations (filename) VALUES %s", [(f,) for f in existing])

    print(f"Creating upcoming catalog ({HORIZON_DAYS} days ahead)...")
    today = datetime.now(IST).date()
    n = insert_services(cur, build_services(today, today + timedelta(days=HORIZON_DAYS - 1), random.Random()))
    print(f"  services created: {n}")
    for t in ("users", "bookings", "seats"):
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        print(f"  {t:10s}{cur.fetchone()[0]}")
    print("\nNext: python scripts/create_admin.py")


# ======================================================================
#  JOB 2: DAILY UPKEEP  (--refresh)
# ======================================================================
def refresh(cur):
    if not table_exists(cur, "services"):
        sys.exit("No tables yet. Run the first build: python scripts/setup_database.py")

    cur.execute("UPDATE bookings SET status='expired' WHERE status='pending' "
                "AND created_at < NOW() - make_interval(mins => %s)", (PENDING_MINUTES,))
    print("pending bookings expired:", cur.rowcount)
    cur.execute("UPDATE seats SET status='available', held_by=NULL, held_until=NULL "
                "WHERE status='held' AND held_until < NOW()")
    print("held seats released:     ", cur.rowcount)
    cur.execute("UPDATE services SET is_active=FALSE WHERE is_active AND start_time < NOW()")
    print("past services hidden:    ", cur.rowcount)
    cur.execute("""UPDATE services s SET available_seats =
                     (SELECT COUNT(*) FROM seats WHERE service_id=s.id AND status='available')
                   WHERE s.is_active AND s.available_seats <>
                     (SELECT COUNT(*) FROM seats WHERE service_id=s.id AND status='available')""")
    print("seat counters fixed:     ", cur.rowcount)

    today = datetime.now(IST).date()
    cur.execute("SELECT MAX(start_time) FROM services WHERE source='dummy'")
    last = cur.fetchone()[0]
    first_new = (last.astimezone(IST).date() + timedelta(days=1)) if last else today
    last_new = today + timedelta(days=HORIZON_DAYS - 1)
    if first_new > last_new:
        print(f"catalog already covers the next {HORIZON_DAYS} days")
    else:
        n = insert_services(cur, build_services(first_new, last_new, random.Random()))
        print(f"new services added for {first_new} .. {last_new}: {n}")


# ======================================================================
#  JOB 3: DATABASE CHANGES AFTER LAUNCH  (--migrate)
# ======================================================================
def migrate(conn, cur):
    if not table_exists(cur, "users"):
        sys.exit("No tables yet. Run the first build: python scripts/setup_database.py")
    ensure_migrations_table(cur)
    conn.commit()
    cur.execute("SELECT filename FROM schema_migrations")
    done = {r[0] for r in cur.fetchall()}
    pending = sorted(p for p in MIGRATIONS_DIR.glob("*.sql") if p.name not in done)
    if not pending:
        print("Database is up to date.")
    for f in pending:
        try:
            cur.execute(f.read_text(encoding="utf-8"))
            cur.execute("INSERT INTO schema_migrations (filename) VALUES (%s)", (f.name,))
            conn.commit()                                          # each file is all-or-nothing
            print("Applied:", f.name)
        except Exception as e:
            conn.rollback()
            sys.exit(f"FAILED {f.name}: {e}\nNothing from this file was applied. Later files were skipped.")


# ======================================================================
if __name__ == "__main__":
    if not DATABASE_URL:
        sys.exit("DATABASE_URL missing. Create backend/.env first.")
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    if "--refresh" in sys.argv:
        refresh(cur)
    elif "--migrate" in sys.argv:
        migrate(conn, cur)
    else:
        first_build(cur, force="--force" in sys.argv)
    conn.commit()
    conn.close()