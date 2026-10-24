
import itertools, random
from datetime import datetime, timedelta, timezone
from psycopg2.extras import execute_values, Json

IST = timezone(timedelta(hours=5, minutes=30))

MAIN_CITIES  = ["Ahmedabad", "Delhi", "Mumbai", "Bengaluru", "Hyderabad"]
ALL_CITIES   = MAIN_CITIES + ["Chennai", "Pune", "Jaipur"]
ROUTES       = list(itertools.permutations(MAIN_CITIES, 2))          # 20 routes

# ---- EDIT THESE LISTS to change what users see on the website ----
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
    """All services for every day from first_day..last_day (dates). Times already past are skipped."""
    now, out = datetime.now(IST), []
    day = first_day
    while day <= last_day:
        # --- flights / buses / trains: every route, every day ---
        for kind, cfg in TRANSPORT.items():
            for o, d in ROUTES:
                route_rng = random.Random(f"{kind}-{o}-{d}")           # same route = similar price every day
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
        # --- metro: 3 trips per city per day ---
        for city in MAIN_CITIES:
            for hour in rng.sample(range(6, 22), 3):
                start = _at(day, hour, rng.choice([0, 20, 40]))
                if start <= now:
                    continue
                a, b = rng.sample(METRO_STATIONS[city], 2)
                out.append(("metro", f"{city} Metro", f"{city} Metro", a, b, city, "standard", start,
                            start + timedelta(minutes=rng.randint(15, 50)), float(rng.choice([20, 30, 40, 50, 60])),
                            round(rng.uniform(3.5, 4.8), 1), {}))
        # --- movies: 3 shows per city per day ---
        for city in MAIN_CITIES:
            for hour in rng.sample([10, 13, 16, 19, 22], 3):
                start = _at(day, hour)
                if start <= now:
                    continue
                t, g = rng.choice(MOVIES)
                out.append(("movie", t, rng.choice(THEATRES), None, None, city, g, start,
                            start + timedelta(hours=2.5), round(rng.uniform(150, 500), -1),
                            round(rng.uniform(3.0, 4.8), 1), {"language": rng.choice(["Hindi", "English", "Gujarati"])}))
        # --- events: 1 per day, random city ---
        t, c = rng.choice(EVENTS)
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
    """Insert services + one seat row per seat. Returns number of services inserted."""
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
                 for r in range(1, rows + 1) for c in cols]          # first 2 rows cost 1.5x
        execute_values(cur, "INSERT INTO seats (service_id, seat_no, seat_class, price_factor) VALUES %s", seats)
    return len(services)