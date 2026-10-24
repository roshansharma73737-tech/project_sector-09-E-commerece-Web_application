"""
scripts/create_admin.py - creates the first admin (never via public signup).
Reads ADMIN_NAME / ADMIN_EMAIL / ADMIN_PASSWORD from backend/.env
Usage: python scripts/create_admin.py
"""
import os, sys
from pathlib import Path
import bcrypt, psycopg2
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")
name, email, pw = os.getenv("ADMIN_NAME"), os.getenv("ADMIN_EMAIL"), os.getenv("ADMIN_PASSWORD")
if not (email and pw):
    sys.exit("Set ADMIN_EMAIL and ADMIN_PASSWORD in backend/.env")
if len(pw) < 10:
    sys.exit("Admin password must be at least 10 characters")

h = bcrypt.hashpw(pw.encode(), bcrypt.gensalt(12)).decode()
conn = psycopg2.connect(os.getenv("DATABASE_URL")); cur = conn.cursor()
cur.execute("""INSERT INTO users (full_name,email,password_hash,role,is_email_verified)
               VALUES (%s,%s,%s,'admin',TRUE)
               ON CONFLICT (email) DO UPDATE SET role='admin', password_hash=EXCLUDED.password_hash
               RETURNING id""", (name or "Admin", email, h))
uid = cur.fetchone()[0]
cur.execute("INSERT INTO user_settings (user_id) VALUES (%s) ON CONFLICT DO NOTHING", (uid,))
cur.execute("INSERT INTO notification_prefs (user_id) VALUES (%s) ON CONFLICT DO NOTHING", (uid,))
conn.commit(); conn.close()
print(f"Admin ready: {email}")
