import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from './schema';
import { logger } from '../utils/logger';

let db: ReturnType<typeof drizzle>;
let pool: Pool;

export async function initializeDatabase() {
  try {
    // Create connection pool
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    // Test connection
    await pool.query('SELECT NOW()');
    logger.info('Database connection established');

    // Initialize Drizzle
    db = drizzle(pool, { schema });
    
    return db;
  } catch (error) {
    logger.error('Failed to initialize database:', error);
    throw error;
  }
}

export function getDb() {
  if (!db) {
    throw new Error('Database not initialized. Call initializeDatabase() first.');
  }
  return db;
}

export async function closeDatabase() {
  if (pool) {
    await pool.end();
    logger.info('Database connection closed');
  }
}

export { schema };