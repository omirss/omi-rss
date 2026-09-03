import { pgTable, uuid, varchar, text, timestamp, boolean, integer, jsonb, index, uniqueIndex, primaryKey, type AnyPgColumn } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';

// Users table
export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  username: varchar('username', { length: 100 }).notNull().unique(),
  passwordHash: varchar('password_hash', { length: 255 }),
  firstName: varchar('first_name', { length: 100 }),
  lastName: varchar('last_name', { length: 100 }),
  avatarUrl: text('avatar_url'),
  role: varchar('role', { length: 50 }).default('user').notNull(),
  isActive: boolean('is_active').default(true).notNull(),
  emailVerified: boolean('email_verified').default(false).notNull(),
  emailVerificationToken: varchar('email_verification_token', { length: 255 }),
  passwordResetToken: varchar('password_reset_token', { length: 255 }),
  passwordResetExpires: timestamp('password_reset_expires'),
  lastLoginAt: timestamp('last_login_at'),
  settings: jsonb('settings').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    emailIdx: index('users_email_idx').on(table.email),
    usernameIdx: index('users_username_idx').on(table.username),
  };
});

// OAuth providers
export const oauthProviders = pgTable('oauth_providers', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  provider: varchar('provider', { length: 50 }).notNull(), // google, github, etc.
  providerId: varchar('provider_id', { length: 255 }).notNull(),
  accessToken: text('access_token'),
  refreshToken: text('refresh_token'),
  expiresAt: timestamp('expires_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    userProviderIdx: uniqueIndex('oauth_user_provider_idx').on(table.userId, table.provider),
    providerIdIdx: uniqueIndex('oauth_provider_id_idx').on(table.provider, table.providerId),
  };
});

// Devices for sync

// Folders
export const folders = pgTable('folders', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 255 }).notNull(),
  parentId: uuid('parent_id').references((): AnyPgColumn => folders.id, { onDelete: 'cascade' }),
  color: varchar('color', { length: 7 }),
  icon: varchar('icon', { length: 50 }),
  position: integer('position').default(0),
  isExpanded: boolean('is_expanded').default(true),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    userIdx: index('folders_user_idx').on(table.userId),
    parentIdx: index('folders_parent_idx').on(table.parentId),
  };
});

// Feeds
export const feeds = pgTable('feeds', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  folderId: uuid('folder_id').references(() => folders.id, { onDelete: 'set null' }),
  url: text('url').notNull(),
  title: varchar('title', { length: 500 }).notNull(),
  description: text('description'),
  siteUrl: text('site_url'),
  favicon: text('favicon'),
  imageUrl: text('image_url'),
  customTitle: varchar('custom_title', { length: 500 }),
  updateInterval: integer('update_interval').default(30), // minutes
  lastFetchedAt: timestamp('last_fetched_at'),
  lastFetchError: text('last_fetch_error'),
  errorCount: integer('error_count').default(0),
  isActive: boolean('is_active').default(true).notNull(),
  settings: jsonb('settings').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    userIdx: index('feeds_user_idx').on(table.userId),
    folderIdx: index('feeds_folder_idx').on(table.folderId),
    urlIdx: index('feeds_url_idx').on(table.url),
  };
});

// Articles
export const articles = pgTable('articles', {
  id: uuid('id').defaultRandom().primaryKey(),
  feedId: uuid('feed_id').notNull().references(() => feeds.id, { onDelete: 'cascade' }),
  guid: text('guid').notNull(),
  url: text('url').notNull(),
  title: text('title').notNull(),
  author: varchar('author', { length: 255 }),
  content: text('content'),
  summary: text('summary'),
  imageUrl: text('image_url'),
  publishedAt: timestamp('published_at'),
  categories: jsonb('categories').default([]),
  enclosures: jsonb('enclosures').default([]),
  metadata: jsonb('metadata').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    feedIdx: index('articles_feed_idx').on(table.feedId),
    guidIdx: uniqueIndex('articles_guid_idx').on(table.feedId, table.guid),
    publishedIdx: index('articles_published_idx').on(table.publishedAt),
  };
});

// User article states
export const userArticleStates = pgTable('user_article_states', {
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  articleId: uuid('article_id').notNull().references(() => articles.id, { onDelete: 'cascade' }),
  isRead: boolean('is_read').default(false).notNull(),
  isStarred: boolean('is_starred').default(false).notNull(),
  readAt: timestamp('read_at'),
  starredAt: timestamp('starred_at'),
  readingTime: integer('reading_time'), // seconds
  scrollPosition: integer('scroll_position').default(0),
  notes: text('notes'),
  highlights: jsonb('highlights').default([]),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    pk: primaryKey({ columns: [table.userId, table.articleId] }),
    userIdx: index('user_article_states_user_idx').on(table.userId),
    articleIdx: index('user_article_states_article_idx').on(table.articleId),
    readIdx: index('user_article_states_read_idx').on(table.isRead),
    starredIdx: index('user_article_states_starred_idx').on(table.isStarred),
  };
});

// Shared folders for collaboration

// Reading statistics
export const readingStats = pgTable('reading_stats', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  date: timestamp('date').notNull(),
  articlesRead: integer('articles_read').default(0).notNull(),
  readingTime: integer('reading_time').default(0).notNull(), // seconds
  wordsRead: integer('words_read').default(0).notNull(),
  feedsVisited: jsonb('feeds_visited').default([]),
  categories: jsonb('categories').default({}),
  hourlyDistribution: jsonb('hourly_distribution').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    userDateIdx: uniqueIndex('reading_stats_user_date_idx').on(table.userId, table.date),
  };
});

// AI analysis results

// Notifications
export const notifications = pgTable('notifications', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  type: varchar('type', { length: 50 }).notNull(), // new_article, keyword_alert, etc.
  title: varchar('title', { length: 255 }).notNull(),
  body: text('body'),
  data: jsonb('data').default({}),
  channels: jsonb('channels').default([]), // ['push', 'email', 'sms']
  status: varchar('status', { length: 50 }).default('pending').notNull(),
  readAt: timestamp('read_at'),
  sentAt: timestamp('sent_at'),
  failedAt: timestamp('failed_at'),
  error: text('error'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => {
  return {
    userIdx: index('notifications_user_idx').on(table.userId),
    statusIdx: index('notifications_status_idx').on(table.status),
    typeIdx: index('notifications_type_idx').on(table.type),
  };
});

// AI article embeddings table for similarity search

// Market watchlist

// Price alerts

// Market quote cache

// Teams

// Team members

// Shared folders

// Define relations
export const usersRelations = relations(users, ({ many }) => ({
  oauthProviders: many(oauthProviders),
  folders: many(folders),
  feeds: many(feeds),
  userArticleStates: many(userArticleStates),
  readingStats: many(readingStats),
  notifications: many(notifications),
}));

export const feedsRelations = relations(feeds, ({ one, many }) => ({
  user: one(users, {
    fields: [feeds.userId],
    references: [users.id],
  }),
  folder: one(folders, {
    fields: [feeds.folderId],
    references: [folders.id],
  }),
  articles: many(articles),
}));

export const articlesRelations = relations(articles, ({ one, many }) => ({
  feed: one(feeds, {
    fields: [articles.feedId],
    references: [feeds.id],
  }),
  userStates: many(userArticleStates),
}));

export const foldersRelations = relations(folders, ({ one, many }) => ({
  user: one(users, {
    fields: [folders.userId],
    references: [users.id],
  }),
  parent: one(folders, {
    fields: [folders.parentId],
    references: [folders.id],
  }),
  children: many(folders),
  feeds: many(feeds),
}));
