// src/core/middleware/rateLimit.js
// Protects the API from floods and password guessing.
const rateLimit = require('express-rate-limit');
const env = require('../configure/env');

const windowMs = env.rateLimit.windowMin * 60 * 1000;

const build = (limit, message) => rateLimit({
  windowMs,
  limit,
  standardHeaders: true,     // sends RateLimit-* headers so the frontend can see the limit
  legacyHeaders: false,
  message: { success: false, message },
});

// For the whole API
const globalLimiter = build(env.rateLimit.max, 'Too many requests. Please try again later.');

// Strict limiter for login, signup, password reset, OTP (used on those routes later)
const authLimiter = build(env.rateLimit.authMax, 'Too many attempts. Please wait and try again.');

module.exports = { globalLimiter, authLimiter };