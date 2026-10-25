// src/config/cors.js
// Only YOUR frontend may call the API from a browser.
const env = require('./env');
const { AppError } = require('../middleware/error');

module.exports = {
  origin(origin, callback) {
    // no Origin header = not a browser page (curl, Postman, server-to-server): allow
    if (!origin || env.frontendUrls.includes(origin)) return callback(null, true);
    return callback(new AppError('Origin not allowed by CORS', 403));
  },
  credentials: true,                                   // allow cookies (refresh token)
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'],
};