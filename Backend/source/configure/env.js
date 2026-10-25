
// src/config/env.js
// Loads backend/.env ONCE, checks the important values, and exports clean settings.
// If something required is missing, the server stops immediately with a clear message
// (better than failing later in the middle of a user's booking).
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env'), quiet: true });

const REQUIRED =  [
    'DATABASE_URL',
    'JWT_ACCESS_SECRET',
    'JWT_REFRESH_SECRET',
    'ENCRYPTION_KEY',
    'TICKET_SIGNING_SECRET',
];

const missing = REQUIRED.filter((key) => !process.env[key]);
if (missing.length) {
  console.error(`\nMissing in backend/.env: ${missing.join(', ')}`);
  console.error('Generate secrets with the command in the backend guide, then restart.\n');
  process.exit(1);
}

if (!/^[0-9a-fA-F]{64}$/.test(process.env.ENCRYPTION_KEY)) {
  console.error('\nENCRYPTION_KEY must be exactly 64 hex characters (32 random bytes).\n');
  process.exit(1);
}

const num = (value, fallback) => {
  const n = Number(value);
  return Number.isFinite(n) && value !== undefined && value !== '' ? n : fallback;
};



module.exports = {
  nodeEnv: process.env.NODE_ENV || 'development',
  isProd: process.env.NODE_ENV === 'production',
  port: num(process.env.PORT, 5000),

  // comma-separated list allowed, e.g. http://localhost:3000,https://mysite.com

  frontendUrls: (process.env.FRONTEND_URL || 'http://localhost:3000')
    .split(',').map((s) => s.trim()).filter(Boolean),

  db: {
    url: process.env.DATABASE_URL,
    ssl: process.env.DB_SSL === 'true',
  },


  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET,
    refreshSecret: process.env.JWT_REFRESH_SECRET,
    accessExpires: process.env.JWT_ACCESS_EXPIRES || '15m',
    refreshExpires: process.env.JWT_REFRESH_EXPIRES || '7d',
  },

  security: {
    bcryptRounds: num(process.env.BCRYPT_ROUNDS, 12),
    encryptionKey: process.env.ENCRYPTION_KEY,
    ticketSigningSecret: process.env.TICKET_SIGNING_SECRET,
    maxLoginAttempts: num(process.env.MAX_LOGIN_ATTEMPTS, 5),
    lockMinutes: num(process.env.LOCK_TIME_MINUTES, 15),
    twoFaAppName: process.env.TWOFA_APP_NAME || 'SECTOR-09',
  },

  rateLimit: {
    windowMin: num(process.env.RATE_LIMIT_WINDOW_MIN, 15),
    max: num(process.env.RATE_LIMIT_MAX, 100),
    authMax: num(process.env.AUTH_RATE_LIMIT_MAX, 5),
  },

  booking: {
    seatHoldMinutes: num(process.env.SEAT_HOLD_MINUTES, 10),
    cancellationWindowHours: num(process.env.CANCELLATION_WINDOW_HOURS, 24),
  },
};