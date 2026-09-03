import { getDb, initializeDatabase, closeDatabase } from './index';
import { users, feeds, folders } from './schema';
import { logger } from '../utils/logger';
import bcrypt from 'bcrypt';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

async function seed() {
  try {
    logger.info('Starting database seeding...');

    // Initialize database connection
    await initializeDatabase();
    const db = getDb();

    // Create demo user
    const passwordHash = await bcrypt.hash('demo123', 10);
    const [demoUser] = await db
      .insert(users)
      .values({
        email: 'demo@omirsss.com',
        username: 'demo',
        passwordHash,
        firstName: 'Demo',
        lastName: 'User',
        emailVerified: true,
        role: 'user',
      })
      .onConflictDoNothing()
      .returning();

    if (demoUser) {
      logger.info('Created demo user:', demoUser.email);

      // Create sample folders
      const [techFolder] = await db
        .insert(folders)
        .values({
          userId: demoUser.id,
          name: 'Technology',
          color: '#3B82F6',
          icon: '💻',
          sortOrder: 1,
        })
        .returning();

      const [newsFolder] = await db
        .insert(folders)
        .values({
          userId: demoUser.id,
          name: 'News',
          color: '#EF4444',
          icon: '📰',
          sortOrder: 2,
        })
        .returning();

      // Create sample feeds
      const sampleFeeds = [
        {
          userId: demoUser.id,
          url: 'https://feeds.arstechnica.com/arstechnica/index',
          title: 'Ars Technica',
          description: 'Serving the Technologist for more than a decade',
          siteUrl: 'https://arstechnica.com',
          folderId: techFolder.id,
        },
        {
          userId: demoUser.id,
          url: 'https://www.theverge.com/rss/index.xml',
          title: 'The Verge',
          description: 'The Verge covers technology, science, art, and culture',
          siteUrl: 'https://www.theverge.com',
          folderId: techFolder.id,
        },
        {
          userId: demoUser.id,
          url: 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml',
          title: 'The New York Times',
          description: 'Breaking News, World News & Multimedia',
          siteUrl: 'https://www.nytimes.com',
          folderId: newsFolder.id,
        },
        {
          userId: demoUser.id,
          url: 'https://feeds.bbci.co.uk/news/rss.xml',
          title: 'BBC News',
          description: 'BBC News - Home',
          siteUrl: 'https://www.bbc.com/news',
          folderId: newsFolder.id,
        },
      ];

      for (const feed of sampleFeeds) {
        await db.insert(feeds).values(feed).onConflictDoNothing();
      }

      logger.info('Created sample feeds and folders');
    }

    logger.info('Database seeding completed successfully');
  } catch (error) {
    logger.error('Database seeding failed:', error);
    throw error;
  } finally {
    await closeDatabase();
    process.exit(0);
  }
}

// Run seed
seed().catch((error) => {
  logger.error('Seed script failed:', error);
  process.exit(1);
});