import { getDb } from '../../src/database';
import { users, feeds, articles, folders, userArticleStates } from '../../src/database/schema';
import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';

export interface TestUser {
  id: string;
  email: string;
  username: string;
  password: string;
  token?: string;
}

export interface TestFeed {
  id: string;
  userId: string;
  url: string;
  title: string;
}

export interface TestArticle {
  id: string;
  feedId: string;
  guid: string;
  title: string;
  url: string;
}

export class TestDataFactory {
  private static userCounter = 0;
  private static feedCounter = 0;
  private static articleCounter = 0;

  static async createUser(overrides: Partial<TestUser> = {}): Promise<TestUser> {
    const db = getDb();
    const counter = ++this.userCounter;
    
    const userData = {
      email: `user${counter}@test.com`,
      username: `testuser${counter}`,
      password: 'Password123!',
      ...overrides,
    };

    const passwordHash = await bcrypt.hash(userData.password, 10);
    
    const [user] = await db
      .insert(users)
      .values({
        id: uuidv4(),
        email: userData.email,
        username: userData.username,
        passwordHash,
        isActive: true,
        emailVerified: true,
      })
      .returning();

    return {
      ...user,
      password: userData.password,
    };
  }

  static async createFeed(userId: string, overrides: Partial<TestFeed> = {}): Promise<TestFeed> {
    const db = getDb();
    const counter = ++this.feedCounter;
    
    const feedData = {
      url: `https://example.com/feed${counter}.xml`,
      title: `Test Feed ${counter}`,
      ...overrides,
    };

    const [feed] = await db
      .insert(feeds)
      .values({
        id: uuidv4(),
        userId,
        url: feedData.url,
        title: feedData.title,
        description: `Description for ${feedData.title}`,
        siteUrl: 'https://example.com',
        isActive: true,
      })
      .returning();

    return feed;
  }

  static async createArticle(feedId: string, overrides: Partial<TestArticle> = {}): Promise<TestArticle> {
    const db = getDb();
    const counter = ++this.articleCounter;
    
    const articleData = {
      guid: `article-${counter}-${Date.now()}`,
      title: `Test Article ${counter}`,
      url: `https://example.com/article${counter}`,
      ...overrides,
    };

    const [article] = await db
      .insert(articles)
      .values({
        id: uuidv4(),
        feedId,
        guid: articleData.guid,
        title: articleData.title,
        url: articleData.url,
        content: `Content for ${articleData.title}`,
        summary: `Summary for ${articleData.title}`,
        author: 'Test Author',
        publishedAt: new Date(),
      })
      .returning();

    return article;
  }

  static async createFolder(userId: string, name: string, parentId?: string) {
    const db = getDb();
    
    const [folder] = await db
      .insert(folders)
      .values({
        id: uuidv4(),
        userId,
        name,
        parentId,
        color: '#000000',
        position: 0,
      })
      .returning();

    return folder;
  }

  static async markArticleAsRead(userId: string, articleId: string) {
    const db = getDb();
    
    await db
      .insert(userArticleStates)
      .values({
        userId,
        articleId,
        isRead: true,
        readAt: new Date(),
      })
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: {
          isRead: true,
          readAt: new Date(),
        },
      });
  }

  static async createTestScenario() {
    // Create a complete test scenario with users, feeds, and articles
    const user1 = await this.createUser({ username: 'alice' });
    const user2 = await this.createUser({ username: 'bob' });

    const feed1 = await this.createFeed(user1.id, { title: 'Tech News' });
    const feed2 = await this.createFeed(user1.id, { title: 'Business Weekly' });
    const feed3 = await this.createFeed(user2.id, { title: 'Science Daily' });

    const articles1 = await Promise.all([
      this.createArticle(feed1.id, { title: 'Latest in AI' }),
      this.createArticle(feed1.id, { title: 'Web Development Trends' }),
      this.createArticle(feed1.id, { title: 'Cloud Computing Update' }),
    ]);

    const articles2 = await Promise.all([
      this.createArticle(feed2.id, { title: 'Market Analysis' }),
      this.createArticle(feed2.id, { title: 'Startup Funding News' }),
    ]);

    const articles3 = await Promise.all([
      this.createArticle(feed3.id, { title: 'Space Exploration' }),
      this.createArticle(feed3.id, { title: 'Climate Research' }),
    ]);

    // Mark some articles as read
    await this.markArticleAsRead(user1.id, articles1[0].id);
    await this.markArticleAsRead(user1.id, articles1[1].id);

    return {
      users: [user1, user2],
      feeds: [feed1, feed2, feed3],
      articles: [...articles1, ...articles2, ...articles3],
    };
  }

  static async cleanup() {
    const db = getDb();
    
    // Delete in correct order to respect foreign key constraints
    await db.delete(userArticleStates);
    await db.delete(articles);
    await db.delete(feeds);
    await db.delete(folders);
    await db.delete(users);
    
    // Reset counters
    this.userCounter = 0;
    this.feedCounter = 0;
    this.articleCounter = 0;
  }
}