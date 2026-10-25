// src/core/middleware/error.js
// One place that turns every error into a safe JSON response.
const env = require('../configure/env');

// Throw this anywhere: throw new AppError('Seat already taken', 409)
class AppError extends Error {
  constructor(message, status = 500) {
    super(message);
    this.status = status;
    this.isOperational = true;   // an expected error with a message safe to show the user
  }
}

// Runs when no route matched the request
function notFound(req, res, next) {
  next(new AppError(`Route not found: ${req.method} ${req.originalUrl}`, 404));
}

// Must have 4 parameters so Express treats it as the error handler
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  let status = err.status || 500;
  let message = err.message;

  if (err.type === 'entity.parse.failed') {            // invalid JSON in the request body
    status = 400; message = 'Invalid JSON in request body';
  } else if (err.type === 'entity.too.large') {
    status = 413; message = 'Request body too large';
  } else if (err.code === '23505') {                   // PostgreSQL: unique violation
    status = 409; message = 'This record already exists';
  } else if (err.code === '23503') {                   // PostgreSQL: foreign key violation
    status = 400; message = 'Related record not found';
  } else if (err.code === '23514' || err.code === '22P02') { // check violation / bad input format
    status = 400; message = 'Invalid data';
  }

  if (status >= 500) {
    console.error(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`, err);
    // never show internal details to users in production
    if (env.isProd || !err.isOperational) message = 'Something went wrong. Please try again.';
  }

  res.status(status).json({
    success: false,
    message,
    ...(env.isProd ? {} : { debug: err.stack }),       // stack trace only while developing
  });
}

module.exports = { AppError, notFound, errorHandler };