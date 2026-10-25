// src/config/database.js
// One shared PostgreSQL connection pool for the whole backend.
const { Pool, types } = require('pg');
const env = require('./env');

// pg returns BIGINT and NUMERIC as strings by default. Convert them so the rest of the
// code works with normal numbers (ids, prices). Safe here: our ids and prices are small.
types.setTypeParser(20, (v) => parseInt(v, 10));    // BIGINT  -> number
types.setTypeParser(1700, (v) => parseFloat(v));    // NUMERIC -> number

const pool = new Pool({
  connectionString: env.db.url,
  ssl: env.db.ssl ? { rejectUnauthorized: false } : false,
  max: 10,                       // max simultaneous connections
  idleTimeoutMillis: 30000, 
  connectionTimeoutMillis: 5000, // fail fast if the database is unreachable
});

pool.on('error', (err) => console.error('Unexpected database error:', err.message));

// Normal query. ALWAYS pass user input in `params`, never inside the SQL text.
//   query('SELECT * FROM users WHERE email = $1', [email])
const query = (text, params) => pool.query(text, params);

// Run several queries as ONE all-or-nothing unit (used for bookings, payments, seat holds).
//   await transaction(async (client) => { await client.query(...); await client.query(...); });
async function transaction(work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function testConnection() {
  const result = await pool.query('SELECT NOW() AS now');
  return result.rows[0].now;
}

module.exports = { pool, query, transaction, testConnection };