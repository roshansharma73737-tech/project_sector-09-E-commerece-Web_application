// server.js - starts the backend. Run with: npm run dev
const env = require('./source/configure/env');       // loads .env first; exits if something is missing
const app = require('./source/app');
const db = require('./source/configure/database');

async function start() {
  try {
    await db.testConnection();                 // do not start if the database is unreachable
    console.log('Database connected');
  } catch (err) {
    console.error('Cannot connect to the database:', err.message);
    console.error('Check DATABASE_URL in backend/.env and that PostgreSQL is running.');
    process.exit(1);
  }

  const server = app.listen(env.port, () => {
    console.log(`Server running on http://localhost:${env.port}  (${env.nodeEnv})`);
  });

  // close cleanly on Ctrl+C or when the host stops the app
  const shutdown = async (signal) => {
    console.log(`\n${signal} received, shutting down...`);
    server.close(async () => {
      await db.pool.end();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();   // force quit if it hangs
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

process.on('unhandledRejection', (reason) => console.error('Unhandled promise rejection:', reason));
start();