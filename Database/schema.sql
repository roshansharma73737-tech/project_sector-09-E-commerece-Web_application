-- The create the schema of the   Total  17 table :-
-- The project the sector -09   in included the  many ticket booking features  book the any type of  ticket from every where :-
-- Run:  psql -U ticket_user -d smart_ticket_booking -f database/schema.sql
-- Safe to re-run: drops everything first (development only!)



-- create the  users  table according to  requiremen  of the related the  authentication  and modules  :- 


DROP TABLE IF EXISTS audit_logs, support_messages, search_history, currency_rates,
  refunds, tickets, payments, passengers, bookings, seats, services,
  notification_prefs, login_history, user_sessions, two_factor,
  user_settings, users CASCADE;

-- ------------------------------------------------------------
-- 1. USERS  (modules/auth, modules/user)
-- ------------------------------------------------------------
CREATE TABLE users (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name          VARCHAR(100)  NOT NULL,
  email              VARCHAR(255)  NOT NULL UNIQUE,
  phone              VARCHAR(20),
  password_hash      VARCHAR(255)  NOT NULL,          -- bcrypt hash, NEVER plain text
  role               VARCHAR(10)   NOT NULL DEFAULT 'user'
  CHECK (role IN ('user','admin')),
  is_email_verified  BOOLEAN       NOT NULL DEFAULT FALSE,
  verify_token_hash  VARCHAR(255),                    -- hashed email-verification token
  reset_token_hash   VARCHAR(255),                    -- hashed password-reset token
  reset_token_expires TIMESTAMPTZ,
  failed_attempts    INT           NOT NULL DEFAULT 0, -- for account lock
  locked_until       TIMESTAMPTZ,
  is_active          BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 2. USER SETTINGS  (account_settings.html: language, region, currency)
-- ------------------------------------------------------------
CREATE TABLE user_settings (
  user_id   BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  language  VARCHAR(10) NOT NULL DEFAULT 'en',
  country   VARCHAR(2)  NOT NULL DEFAULT 'IN',
  currency  VARCHAR(3)  NOT NULL DEFAULT 'INR',
  timezone  VARCHAR(50) NOT NULL DEFAULT 'Asia/Kolkata'
);

-- ------------------------------------------------------------
-- 3. TWO-FACTOR AUTH  (security.html)
-- ------------------------------------------------------------
CREATE TABLE two_factor (
  user_id           BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  secret_encrypted  TEXT        NOT NULL,             -- encrypted with ENCRYPTION_KEY
  is_enabled        BOOLEAN     NOT NULL DEFAULT FALSE,
  backup_codes_hash TEXT[],                           -- hashed one-time backup codes
  enabled_at        TIMESTAMPTZ
);

-- -----------------------------------------------------------
-- 4. ACTIVE SESSIONS / DEVICES  (sessions.html)
--    One row per refresh token, so a device can be revoked instantly
-- ------------------------------------------------------------
CREATE TABLE user_sessions (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id             BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash  VARCHAR(255) NOT NULL,          -- hashed, never raw
  device_name         VARCHAR(100),
  browser             VARCHAR(50),
  os                  VARCHAR(50),
  ip_address          VARCHAR(45),
  is_revoked          BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at          TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_sessions_user ON user_sessions(user_id);

-- ------------------------------------------------------------
-- 5. LOGIN HISTORY / SECURITY EVENTS  (security.html)
-- ------------------------------------------------------------
CREATE TABLE login_history (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id) ON DELETE CASCADE,
  event_type  VARCHAR(30) NOT NULL,   -- login_success, login_failed, password_changed, 2fa_enabled...
  ip_address  VARCHAR(45),
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_login_hist_user ON login_history(user_id, created_at DESC);

-- ------------------------------------------------------------
-- 6. NOTIFICATION PREFERENCES  (notifications.html)
-- ------------------------------------------------------------
CREATE TABLE notification_prefs (
  user_id           BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  email_booking     BOOLEAN NOT NULL DEFAULT TRUE,
  email_promotions  BOOLEAN NOT NULL DEFAULT FALSE,
  sms_booking       BOOLEAN NOT NULL DEFAULT FALSE,
  sms_security      BOOLEAN NOT NULL DEFAULT FALSE,
  push_enabled      BOOLEAN NOT NULL DEFAULT FALSE
  -- security emails (new login, password change) are always sent, so no column
);

-- ------------------------------------------------------------
-- 7. SERVICES: one table for everything bookable
--    flight / bus / train / metro / movie / event
--    (search.html?type=...)
-- ---------------------------------    ---------------------------
CREATE TABLE services (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  type             VARCHAR(10)  NOT NULL
                   CHECK (type IN ('flight','bus','train','metro','movie','event')),
  title            VARCHAR(150) NOT NULL,       -- "IndiGo 6E-201", "Avengers", "Tech Meetup"
  provider         VARCHAR(100),                -- airline / bus operator / theatre / organiser
  origin           VARCHAR(80),                 -- for transport
  destination      VARCHAR(80),                 -- for transport
  city             VARCHAR(80),                 -- for movie / event
  category         VARCHAR(50),                 -- concert, action, sleeper, economy...
  start_time       TIMESTAMPTZ  NOT NULL,
  end_time         TIMESTAMPTZ,
  base_price       NUMERIC(10,2) NOT NULL CHECK (base_price >= 0),
  currency         VARCHAR(3)   NOT NULL DEFAULT 'INR',
  total_seats      INT          NOT NULL CHECK (total_seats > 0),
  available_seats  INT          NOT NULL CHECK (available_seats >= 0),
  rating           NUMERIC(2,1),
  details          JSONB        NOT NULL DEFAULT '{}',  -- extra fields (cast, venue, stops...)
  is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CHECK (available_seats <= total_seats)
);
CREATE INDEX idx_services_search ON services(type, origin, destination, start_time);
CREATE INDEX idx_services_city   ON services(type, city, start_time);

-- ------------------------------------------------------------
-- 8. SEATS  (details.html seat selection)
--    status flow: available -> held (10 min) -> booked
--    held_until lets the server auto-release abandoned seats
-- ------------------------------------------------------------
CREATE TABLE seats (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  service_id    BIGINT NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  seat_no       VARCHAR(10) NOT NULL,                -- 12A, B5...
  seat_class    VARCHAR(20) NOT NULL DEFAULT 'standard',
  price_factor  NUMERIC(4,2) NOT NULL DEFAULT 1.00,  -- premium seats cost more
  status        VARCHAR(10) NOT NULL DEFAULT 'available'
                CHECK (status IN ('available','held','booked')),
  held_by       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  held_until    TIMESTAMPTZ,
  UNIQUE (service_id, seat_no)                       -- same seat can't exist twice
);
CREATE INDEX idx_seats_service ON seats(service_id, status);

-- ------------------------------------------------------------
-- 9. BOOKINGS  (booking.html, my-account.html)
-- ------------------------------------------------------------
    

CREATE TABLE bookings (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_ref      VARCHAR(12) NOT NULL UNIQUE,      -- shown to user e.g. STB-7K2M9Q
  user_id          BIGINT NOT NULL REFERENCES users(id),
  service_id       BIGINT NOT NULL REFERENCES services(id),
  status           VARCHAR(12) NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','confirmed','cancelled','expired')),
  total_amount     NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),  -- calculated by SERVER
  currency         VARCHAR(3)  NOT NULL DEFAULT 'INR',
  idempotency_key  VARCHAR(64) UNIQUE,               -- blocks duplicate bookings on retry/double-click
  contact_email    VARCHAR(255),
  contact_phone    VARCHAR(20),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_at     TIMESTAMPTZ
);
CREATE INDEX idx_bookings_user ON bookings(user_id, created_at DESC);

-- ------------------------------------------------------------
-- 10. PASSENGERS (one row per seat in a booking)
-- ------------------------------------------------------------
CREATE TABLE passengers (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id  BIGINT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  seat_id     BIGINT REFERENCES seats(id),
  full_name   VARCHAR(100) NOT NULL,
  age         INT CHECK (age BETWEEN 0 AND 120),
  gender      VARCHAR(10)
);

-- ------------------------------------------------------------
-- 11. PAYMENTS  (payment.html, QR payment)
-- ------------------------------------------------------------
CREATE TABLE payments (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id          BIGINT NOT NULL REFERENCES bookings(id),
  method              VARCHAR(10) NOT NULL CHECK (method IN ('card','upi','wallet','qr','netbanking')),
  amount              NUMERIC(10,2) NOT NULL,        -- amount actually charged
  currency            VARCHAR(3)  NOT NULL,          -- currency charged
  exchange_rate       NUMERIC(12,6) NOT NULL DEFAULT 1, -- rate locked at payment time
  status              VARCHAR(10) NOT NULL DEFAULT 'created'
                      CHECK (status IN ('created','pending','success','failed','refunded')),
  gateway_order_id    VARCHAR(100),                  -- Razorpay order id
  gateway_payment_id  VARCHAR(100),                  -- Razorpay payment id (no card data stored!)
  qr_token_hash       VARCHAR(255),                  -- single-use QR payment token (hashed)
  qr_expires_at       TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paid_at             TIMESTAMPTZ
);
CREATE INDEX idx_payments_booking ON payments(booking_id);

-- ------------------------------------------------------------
-- 12. REFUNDS
-- ------------------------------------------------------------
CREATE TABLE refunds (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id  BIGINT NOT NULL REFERENCES payments(id),
  booking_id  BIGINT NOT NULL REFERENCES bookings(id),
  amount      NUMERIC(10,2) NOT NULL,
  fee         NUMERIC(10,2) NOT NULL DEFAULT 0,      -- cancellation fee kept
  status      VARCHAR(12) NOT NULL DEFAULT 'initiated'
              CHECK (status IN ('initiated','processed','failed')),
  reason      VARCHAR(200),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 13. TICKETS (tickets.html) - one per passenger after payment success
-- ------------------------------------------------------------
CREATE TABLE tickets (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id    BIGINT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  passenger_id  BIGINT NOT NULL REFERENCES passengers(id) ON DELETE CASCADE,
  ticket_code   VARCHAR(40) NOT NULL UNIQUE,         -- value inside the QR
  signature     VARCHAR(128) NOT NULL,               -- HMAC so the QR can't be forged
  status        VARCHAR(10) NOT NULL DEFAULT 'valid'
                CHECK (status IN ('valid','used','cancelled')),
  used_at       TIMESTAMPTZ,
  issued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 14. SUPPORTING TABLES
-- ------------------------------------------------------------
CREATE TABLE search_history (                         -- feeds recommendations
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id) ON DELETE CASCADE,
  type        VARCHAR(10) NOT NULL,
  query       JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE support_messages (                       -- chatbot + contact form
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  sender      VARCHAR(10) NOT NULL CHECK (sender IN ('user','bot','contact')),
  message     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE currency_rates (                         -- cached by currency.client.js
  currency    VARCHAR(3) PRIMARY KEY,
  rate_to_inr NUMERIC(14,6) NOT NULL,                 -- how many INR for 1 unit
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_logs (                             -- admin / refund / cancel actions
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  action      VARCHAR(60) NOT NULL,
  details     JSONB,
  ip_address  VARCHAR(45),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
  

CREATE VIEW v_upcoming_services AS                 -- what users can book RIGHT NOW
SELECT * FROM services WHERE is_active AND start_time > NOW();


CREATE VIEW v_upcoming_occupancy AS                -- how full upcoming services are
SELECT id, type, title, origin, destination, city, start_time, total_seats, available_seats,
       ROUND(100.0 * (total_seats - available_seats) / total_seats, 1) AS occupancy_pct
FROM v_upcoming_services;


CREATE VIEW v_revenue_last_30_days AS              -- real paid bookings per day
SELECT DATE(p.paid_at) AS day, COUNT(*) AS paid_bookings, SUM(b.total_amount) AS revenue
FROM payments p JOIN bookings b ON b.id = p.booking_id
WHERE p.status = 'success' AND p.paid_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(p.paid_at) ORDER BY day DESC;


CREATE VIEW v_top_routes_30_days AS                -- most booked routes, last 30 days
SELECT s.type, s.origin, s.destination, COUNT(*) AS bookings, SUM(b.total_amount) AS revenue
FROM bookings b JOIN services s ON s.id = b.service_id
WHERE b.status = 'confirmed' AND b.created_at >= NOW() - INTERVAL '30 days' AND s.origin IS NOT NULL
GROUP BY s.type, s.origin, s.destination ORDER BY bookings DESC;