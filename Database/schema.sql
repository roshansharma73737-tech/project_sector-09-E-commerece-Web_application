-- The create the schema of the   Total  17 table :-
-- The project the sector -09   in included the  many ticket booking features  book the any type of  ticket from every where :-
-- Run:  psql -U ticket_user -d smart_ticket_booking -f database/schema.sql
-- Safe to re-run: drops everything first (development only!)



-- create the  users  table according to  requiremen  of the related the  authentication  and modules  :- 

CREATE TABLE users(
    id    BIGINT GENERATED ALWAYS AS IDENTITY  PRIMARY KEY,
    full_name  VARCHAR(100)  NOT NULL,
    email      VARCHAR(255)  NOT NULL UNIQUE,
    phone      VARCHAR(20),
    password_hash   VARCHAR(255) NOT NULL,
    role  VARCHAR (10) NOT NULL DEFAULT  'user'
    is_email_verifield BOOLEAN  NOT NULL DEFAULT FALSE,
    verify_token_hash  VARCHAR(255),    
    reset_token_hash VARCHAR(255),
    reset_token_expire TIMESTAMPTZ,
    failed_attempts INT NOT NULL DEFAULT 0,
    lock_until   TIMESTAMPTZ,
    is_active  BOOLEAN  NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT  NULL DEFAULT NOW()
);


-- CREATE THE TABLE OF THE   USER REGION AND CURRENCY EXCHANGE  ACCORDING TO  LANGUAGES :- 
CREATE  TABLE user_setting(
    user_id  BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL  DEFAULT 'en',
    country      VARCHAR(2) NOT  NULL  DEFAULT 'IN',
    currency  VARCHAR(3) NOT NULL  DEFAULT 'INR',
    timezone  VARCHAR(50) NOT NULL DEFAULT 'Asia/Kolkata'
);


-- CREATE THE FEATURESS ACCORDING TO THE    TWO FACTOR  AUTHENTICATION   FOR THE  ( SECURITY ):- 
CREATE TABLE two_factor(
    user_id      BIGINT PRIMARY KEY  REFERENCES  users(id) ON DELETE CASCADE,
    secret_encrypted TEXT  NOT NULL ,
    is_enabled BOOLEAN  NOT NULL DEFAULT FALSE,
    backup_codes_hash TEXT[],
    enabled_at TIMESTAMPTZ

);
CREATE TABLE user_session (
    id     BIGINT GENERATED  ALWAYS AS IDENTITY  PRIMARY KEY,
    user_id  BIGINT  NOT NULL  REFERENCES  user(id) ON DELETE  CASCADE,
    refresh_token_hash VARCHAR(225) NOT NULL,
    device_name  VARCHAR(100),
    browser   VARCHAR(50),
    OS      VARCHAR(50),
    ip_address  VARCHAR(45),
    is_revoked  BOOLEAN   NOT NULL  DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL  DEFAULT NOW(),
    last_active TIMESTAMPTZ NOT NULL  DEFAULT NOW(),
    expire_at  TIMESTAMPTZ NOT NULL 
);
CREATE INDEX idx_session ON user_session(user_id);



CREATE TABLE notification_pref(
    user_id BIGINT PRIMARY KEY  REFERENCES  user(id) ON DELETE  CASCADE,
    eamil_booking  BOOLEAN NOT NULL DEFAULT  TRUE,
    email_promotions  BOOLEAN NOT NULL DEFAULT FALSE,
    sms_booking   BOOLEAN NOT NULL DEFAULT FALSE,
    sms_security  BOOLEAN NOT NULL  DEFAULT FALSE,
    push_enabled BOOLEAN NOT NULL  DEFAULT FALSE

);


-- IN THE  THIS TABLE  ALL MENTION  THE  ALL SERVICES   IN THE   ONE  TABLE  RELATED ( train , flight ,  metro , movies , events  ,bus )
--  all included in the one table -->
 
CREATE TABLE services (
    id    BIGINT GENERATED ALWAYS AS IDENTITY  PRIMARY KEY,
    type  VARCHAR(10) NOT NULL CHECK  (type IN('FLIGHT',  'BUS',  'TRAIN', 'METRO',' MOVIE','EVENT')),
    title VARCHAR(150) NOT NULL     
    provider VARCHAR(100),
    origin  VARCHAR(100),
    destination VARCHAR(100), 
    city   VARCHAR(100),
    category VARCHAR(50),
    start_time   TIMESTAMPTZ NOT NULL,
    end_time     TIMESTAMPTZ,
    base_price  NUMERIC(10,2)  NOT NULL CHECK ( base_price >= 0),
    currency  VARCHAR (3) NOT NULL DEFAULT 'INR',
    total_seat  INT   NOT NULL   CHECK (total_seat > 0),
    avialable_seats INT NOT NULL CHECK (avialable_seats >=0),   
    rating    NUMERIC(2,1),
    details   JSONB NOT NULL DEFAULT '{ }',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

);
CREATE INDEX idx_service_search ON services(type,origin, destination , start_time);
CREATE INDEX idx_service_city  ON services(type, city,start_time );



-- CREATE  THE TABLE OF THE SEATS  related the all services ( events , movies ,  flight , trian , metro )  included in one table 
CREATE TABLE  seats (
    id  BIGINT GENERATED ALWAYS AS  IDENTITY  PRIMARY KEY,
    service_id   BIGINT  NOT NULL  REFERENCES  services(id) ON DELETE CASCADE,
    seat_no VARCHAR(10) NOT NULL,   
    seat_class VARCHAR(20) NOT NULL  DEFAULT 'standard',
    price_factor NUMERIC(4,2 ) NOT NULL  DEFAULT 1:00,
    status   VARCHAR(10) NOT NULL  DEFAULT 'available' CHECK (status IN ('avialable','held', 'booked')),
    held_by  BIGINT  REFERENCES users(id) ON DELETE  SET NULL,
    held_until TIMESTAMPTZ,
    UNIQUE (service_id,seat_no )
);

CREATE  INDEX  idx_seats_service ON seats(service_id, status);



--CREATE THE BOOKING TABLE  TO RECORDED THE ENTERIES IN THE DATABASE
CREATE TABLE booking (
    id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY ,
    bokking_ref   VARCHAR(12) NOT NULL  UNIQUE
    user_id BIGINT  NOT NULL REFERENCES users(id),
    service_id   BIGINT NOT NULL  services(id),
    status  VARCHAR (12) NOT NULL CHECK (status IN ('pending','confirmed ', 'cancelled ','expired')),
    total_amount  NUMERIC(10,2) NOT NULL  CHECK (total_amount  >=0),
    currency  VARCHAR(3) NOT NULL DEFAULT 'INR',
    idemoptency_key  VARCHAR(70) UNIQUE ,
    contact_no   VARCHAR (15) ,
    contact_email  VARCHAR(225) ,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW( ),
    cancelled_at TIMESTAMPTZ ,
    updated_at  TIMESTAMPTZ NOT NULL 

);
CREATE  INDEX idx_booking_users ON booking(user_id,created_at DESC)
 

--  passengers details store -

CREATE TABLE passengers (
    id  BIGINT GENERATED  ALWAYS AS  IDENTITY  PRIMARY KEY,
    booking_id  BIGINT  NOT NULL REFERENCES  booking(id) ON DELETE CASCADE,
    seat_id BIG =INT NOT NULL REFERENCES seats(id),
    full_name  VARCHAR(100) NOT NULL,
    age   INT CHECK (age  BETWEEN 0 AND 120),
    gender  VARCHAR(10),
);


-- IN PAYMENTS THE  INCLUDED THE PAYMENTS DETAILS :-

CREATE TABLE payments (
    id   BIGINT  GENERATED ALWAYS AS PRIMARY KEY,
    booking_id  BIGINT REFERENCES  booking(id),
    method    VARCHAR(10 ) NOT NULL  CHECK (method IN ('card ','upi','wallet','qr','netbanking ')),
    currency    VARCHAR(3) NOT NULL ,
    exchange_rate  NUMERIC (12,6) NOT NULL  DEFAULT 1,
    status  VARCHAR(10) NOT NULL  DEFAULT 'created ' CHECK (status  IN ('created', 'sucess','pending', 'failed', 'refunded')),
    getway_order_id   VARCHAR(225),
    getway_payment_id VARCHAR(255),
    qr_token_hash  VARCHAR(255),
    qr_expire_at  TIMESTAMPTZ ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    paid_At TIMESTAMPTZ     
);

CREATE  INDEX  idx_payments ON payments(booking_id);

-- CREATE   THE REFUND  SYSTEM  ACCORDING TO  THE REQUIREMENTS :-

CREATE  TABLE   refund (
    id  BIGINT  GENERATED ALWAYS AS  PRIMARY KEY ,
    payment_id   BIGINT  NOT  NULL REFERENCES  payments(id),
    booking_id  BIGINT NOT NULL REFERENCES  booking(id),
    amount   NUMERIC(10,2) NOT NULL ,
    fee  NUMERIC(10,2) NOT NULL, 
    status  VARCHAR(12) NOT NULL  DEFAULT  'intiated', CHECK (status IN( 'intiated', 'processes','failed' )),
    reason  VARCHAR(1000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- THE  TABLE RECORED THE   TICKET DETAILS :-

CREATE  TABLE  tickets(
    id  BIGINT  GENERATED ALWAYS AS PRIMARY KEY ,
    booking_id  BIGINT  NOT NULL  REFERENCES  booking(id) ON DELETE CASCADE,
    passengers_id  BIGINT NOT NULL REFERENCES  passengers(id) ON DELETE CASCADE,
    ticket_Code  VARCHAR(40 ) NOT NULL   UNIQUE ,
    signature  VARCHAR(130)NOT NULL ,
    status  VARCHAR (40) NOT NULL  DEFAULT 'valid' CHECK (status IN ('valid','used', 'cancelled')),
    user_at TIMESTAMPTZ ,
    issued_at TIMESTAMPTZ DEFAULT NOW()
);



-- SUPPORTING TABLES    4 TABLE REQUIRED NOT  COMPULSORY :-
