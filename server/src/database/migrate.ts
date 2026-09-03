import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { getDb, initializeDatabase } from './index';
import { logger } from '../utils/logger';
import path from 'path';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

async function main() {
  try {
    logger.info('Starting database migration...');

    // Initialize database connection
    await initializeDatabase();
    const db = getDb();

    // Run migrations
    await migrate(db, {
      migrationsFolder: path.join(__dirname, '../../drizzle'),
    });

    logger.info('Database migration completed successfully');
    process.exit(0);
  } catch (error) {
    logger.error('Database migration failed:', error);
    process.exit(1);
  }
}

main();