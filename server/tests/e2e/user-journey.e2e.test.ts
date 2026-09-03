import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { Express } from 'express';
import { createTestServer } from '../helpers/testServer';
import { TestDataFactory } from '../helpers/testData';

describe('User Journey E2E Tests', () => {
  let app: Express;
  let authToken: string;
  let userId: string;
  let feedId: string;
  let articleId: string;

  beforeAll(async () => {
    app = await createTestServer();
    await TestDataFactory.cleanup();
  });

  afterAll(async () => {
    await TestDataFactory.cleanup();
  });

  describe('Complete User Journey', () => {
    it('Step 1: User Registration', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'journey@example.com',
          username: 'journeyuser',
          password: 'JourneyPass123!',
          firstName: 'Journey',
          lastName: 'User',
        })
        .expect(201);

      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      
      authToken = response.body.token;
      userId = response.body.user.id;
    });

    it('Step 2: Add First RSS Feed', async () => {
      const response = await request(app)
        .post('/api/feeds')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          url: 'https://feeds.bbci.co.uk/news/rss.xml',
          folderId: null,
        })
        .expect(201);

      expect(response.body).toHaveProperty('feed');
      expect(response.body.feed).toHaveProperty('title');
      
      feedId = response.body.feed.id;
    });

    it('Step 3: Fetch Feed Articles', async () => {
      const response = await request(app)
        .get('/api/articles')
        .set('Authorization', `Bearer ${authToken}`)
        .query({
          feedId,
          limit: 10,
        })
        .expect(200);

      expect(response.body).toHaveProperty('articles');
      expect(response.body.articles).toBeInstanceOf(Array);
      
      if (response.body.articles.length > 0) {
        articleId = response.body.articles[0].id;
      }
    });

    it('Step 4: Mark Article as Read', async () => {
      if (!articleId) {
        console.log('No articles to mark as read');
        return;
      }

      await request(app)
        .put(`/api/articles/${articleId}/state`)
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          isRead: true,
        })
        .expect(200);

      // Verify the article is marked as read
      const response = await request(app)
        .get(`/api/articles/${articleId}`)
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body.article.state).toHaveProperty('isRead', true);
    });

    it('Step 5: Star an Article', async () => {
      if (!articleId) {
        console.log('No articles to star');
        return;
      }

      await request(app)
        .put(`/api/articles/${articleId}/state`)
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          isStarred: true,
        })
        .expect(200);
    });

    it('Step 6: Create Folders', async () => {
      const techFolder = await request(app)
        .post('/api/folders')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          name: 'Technology',
          color: '#0066cc',
        })
        .expect(201);

      const newsFolder = await request(app)
        .post('/api/folders')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          name: 'News',
          color: '#cc0000',
        })
        .expect(201);

      expect(techFolder.body.folder).toHaveProperty('name', 'Technology');
      expect(newsFolder.body.folder).toHaveProperty('name', 'News');
    });

    it('Step 7: Get Reading Statistics', async () => {
      const response = await request(app)
        .get('/api/stats/overview')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body).toHaveProperty('stats');
      expect(response.body.stats).toHaveProperty('totalArticles');
      expect(response.body.stats).toHaveProperty('readArticles');
      expect(response.body.stats).toHaveProperty('starredArticles');
    });

    it('Step 8: Search Articles', async () => {
      const response = await request(app)
        .get('/api/articles/search')
        .set('Authorization', `Bearer ${authToken}`)
        .query({
          q: 'technology',
          limit: 5,
        })
        .expect(200);

      expect(response.body).toHaveProperty('articles');
      expect(response.body).toHaveProperty('total');
    });

    it('Step 9: Update User Profile', async () => {
      const response = await request(app)
        .patch('/api/users/profile')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          firstName: 'Updated',
          lastName: 'Journey',
          settings: {
            theme: 'dark',
            articleView: 'card',
          },
        })
        .expect(200);

      expect(response.body.user).toHaveProperty('firstName', 'Updated');
      expect(response.body.user.settings).toHaveProperty('theme', 'dark');
    });

    it('Step 10: Export OPML', async () => {
      const response = await request(app)
        .get('/api/feeds/export/opml')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.headers['content-type']).toContain('application/xml');
      expect(response.text).toContain('<?xml');
      expect(response.text).toContain('<opml');
    });
  });

  describe('Error Scenarios', () => {
    it('should handle invalid feed URL gracefully', async () => {
      const response = await request(app)
        .post('/api/feeds')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          url: 'not-a-valid-url',
        })
        .expect(400);

      expect(response.body).toHaveProperty('error');
    });

    it('should prevent accessing other users data', async () => {
      // Create another user
      const otherUser = await TestDataFactory.createUser();
      const otherFeed = await TestDataFactory.createFeed(otherUser.id);

      // Try to access other user's feed
      await request(app)
        .get(`/api/feeds/${otherFeed.id}`)
        .set('Authorization', `Bearer ${authToken}`)
        .expect(404);
    });

    it('should handle rate limiting', async () => {
      // Make many requests quickly
      const requests = Array(20).fill(null).map(() =>
        request(app)
          .get('/api/articles')
          .set('Authorization', `Bearer ${authToken}`)
      );

      const responses = await Promise.all(requests);
      const rateLimited = responses.some(r => r.status === 429);
      
      // Should hit rate limit eventually
      expect(rateLimited).toBe(true);
    });
  });

  describe('Performance Tests', () => {
    it('should handle large article lists efficiently', async () => {
      const startTime = Date.now();
      
      const response = await request(app)
        .get('/api/articles')
        .set('Authorization', `Bearer ${authToken}`)
        .query({
          limit: 100,
        })
        .expect(200);

      const duration = Date.now() - startTime;
      
      expect(duration).toBeLessThan(1000); // Should respond within 1 second
      expect(response.body).toHaveProperty('articles');
    });

    it('should paginate results properly', async () => {
      const page1 = await request(app)
        .get('/api/articles')
        .set('Authorization', `Bearer ${authToken}`)
        .query({
          limit: 10,
          offset: 0,
        })
        .expect(200);

      const page2 = await request(app)
        .get('/api/articles')
        .set('Authorization', `Bearer ${authToken}`)
        .query({
          limit: 10,
          offset: 10,
        })
        .expect(200);

      // Articles should be different
      if (page1.body.articles.length > 0 && page2.body.articles.length > 0) {
        expect(page1.body.articles[0].id).not.toBe(page2.body.articles[0].id);
      }
    });
  });
});