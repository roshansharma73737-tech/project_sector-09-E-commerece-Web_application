// src/app.js
// Builds the Express app: security middleware, routes, error handling.
// (server.js starts it; keeping them apart makes the app easy to reuse.)
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const cookieParser = require('cookie-parser');

const env = require('./configure/env');
const corsOptions = require('./configure/cors');
const db = require('./configure/database');
const { globalLimiter } = require('./middleware/');
const { notFound, errorHandler } = require('./middleware/error');

const app = express();

// ---- security + parsing (order matters) ----
app.use(helmet());                                   // safe HTTP headers
app.use(cors(corsOptions));                          // only our frontend
app.use(morgan(env.isProd ? 'combined' : 'dev'));    // request log
app.use(express.json({ limit: '100kb' }));           // JSON bodies, small limit
app.use(cookieParser());
app.use('/api', globalLimiter);                      // rate limit every API route

// ---- health check: proves the server AND the database are working ----
app.get('/api/health', async (req, res) => {
  try {
    const time = await db.testConnection();
    const { rows } = await db.query('SELECT COUNT(*)::int AS upcoming FROM v_upcoming_services');
    res.json({
      status: 'ok',
      database: 'connected',
      serverTime: time,
      upcomingServices: rows[0].upcoming,            // 0 means run scripts/setup_db.py / refresh_catalog.py
    });
  } catch (err) {
    console.error('Health check failed:', err.message);
    res.status(503).json({ status: 'error', database: 'unreachable' });
  }
});

// ---- feature routes are added here, one line per module, as we build them ----
// app.use('/api/auth',     require('./modules/auth/auth.routes'));
// app.use('/api/user',     require('./modules/user/user.routes'));
// app.use('/api/flights',  require('./modules/flights/flights.routes'));
// ...

// ---- must stay LAST ----
app.use(notFound);
app.use(errorHandler);

module.exports = app;