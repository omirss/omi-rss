import { pgTable, uuid, varchar, text, timestamp, boolean, integer, jsonb, index, uniqueIndex, primaryKey, decimal, bigint, unique } from 'drizzle-orm/pg-core';
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
export const devices = pgTable('devices', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 100 }).notNull(),
  type: varchar('type', { length: 50 }).notNull(), // web, mobile, extension
  deviceId: varchar('device_id', { length: 255 }).notNull().unique(),
  lastSyncAt: timestamp('last_sync_at'),
  isActive: boolean('is_active').default(true).notNull(),
  metadata: jsonb('metadata').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    userIdx: index('devices_user_idx').on(table.userId),
    deviceIdIdx: index('devices_device_id_idx').on(table.deviceId),
  };
});

// Folders
export const folders = pgTable('folders', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 255 }).notNull(),
  parentId: uuid('parent_id').references(() => folders.id, { onDelete: 'cascade' }),
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
export const sharedFolders = pgTable('shared_folders', {
  id: uuid('id').defaultRandom().primaryKey(),
  folderId: uuid('folder_id').notNull().references(() => folders.id, { onDelete: 'cascade' }),
  sharedByUserId: uuid('shared_by_user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  sharedWithUserId: uuid('shared_with_user_id').references(() => users.id, { onDelete: 'cascade' }),
  shareToken: varchar('share_token', { length: 255 }).unique(),
  permissions: jsonb('permissions').default({ read: true, write: false, admin: false }),
  acceptedAt: timestamp('accepted_at'),
  expiresAt: timestamp('expires_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    folderIdx: index('shared_folders_folder_idx').on(table.folderId),
    sharedByIdx: index('shared_folders_shared_by_idx').on(table.sharedByUserId),
    sharedWithIdx: index('shared_folders_shared_with_idx').on(table.sharedWithUserId),
    tokenIdx: index('shared_folders_token_idx').on(table.shareToken),
  };
});

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
export const aiAnalysis = pgTable('ai_analysis', {
  id: uuid('id').defaultRandom().primaryKey(),
  articleId: uuid('article_id').notNull().references(() => articles.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  provider: varchar('provider', { length: 50 }).notNull(), // openai, anthropic, google
  analysisType: varchar('analysis_type', { length: 50 }).notNull(), // summary, sentiment, etc.
  result: jsonb('result').notNull(),
  tokens: integer('tokens').default(0),
  cost: integer('cost').default(0), // in cents
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => {
  return {
    articleIdx: index('ai_analysis_article_idx').on(table.articleId),
    userIdx: index('ai_analysis_user_idx').on(table.userId),
  };
});

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
export const aiArticleEmbeddings = pgTable('ai_article_embeddings', {
  articleId: uuid('article_id').references(() => articles.id, { onDelete: 'cascade' }).primaryKey(),
  embedding: jsonb('embedding').notNull(), // Store as JSONB for now, use pgvector in production
  model: varchar('model', { length: 100 }).notNull(),
  provider: varchar('provider', { length: 50 }).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

// Market watchlist
export const marketWatchlists = pgTable('market_watchlists', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  symbol: varchar('symbol', { length: 20 }).notNull(),
  assetType: varchar('asset_type', { length: 20 }).notNull(),
  name: varchar('name', { length: 255 }),
  sortOrder: integer('sort_order').default(0),
  addedAt: timestamp('added_at').defaultNow().notNull(),
}, (table) => {
  return {
    userSymbolUnique: unique('market_watchlist_user_symbol_unique').on(table.userId, table.symbol),
    userIdx: index('market_watchlist_user_idx').on(table.userId),
  };
});

// Price alerts
export const priceAlerts = pgTable('price_alerts', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  symbol: varchar('symbol', { length: 20 }).notNull(),
  assetType: varchar('asset_type', { length: 20 }).notNull(),
  alertType: varchar('alert_type', { length: 50 }).notNull(),
  value: decimal('value', { precision: 20, scale: 8 }).notNull(),
  message: text('message'),
  isActive: boolean('is_active').default(true).notNull(),
  triggeredAt: timestamp('triggered_at'),
  triggeredPrice: decimal('triggered_price', { precision: 20, scale: 8 }),
  expiresAt: timestamp('expires_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => {
  return {
    userIdx: index('price_alerts_user_idx').on(table.userId),
    activeIdx: index('price_alerts_active_idx').on(table.isActive),
    symbolIdx: index('price_alerts_symbol_idx').on(table.symbol),
  };
});

// Market quote cache
export const marketQuoteCache = pgTable('market_quote_cache', {
  id: uuid('id').defaultRandom().primaryKey(),
  symbol: varchar('symbol', { length: 20 }).notNull(),
  assetType: varchar('asset_type', { length: 20 }).notNull(),
  price: decimal('price', { precision: 20, scale: 8 }).notNull(),
  change: decimal('change', { precision: 20, scale: 8 }),
  changePercent: decimal('change_percent', { precision: 10, scale: 4 }),
  volume: bigint('volume', { mode: 'number' }),
  high: decimal('high', { precision: 20, scale: 8 }),
  low: decimal('low', { precision: 20, scale: 8 }),
  open: decimal('open', { precision: 20, scale: 8 }),
  previousClose: decimal('previous_close', { precision: 20, scale: 8 }),
  marketCap: bigint('market_cap', { mode: 'number' }),
  provider: varchar('provider', { length: 50 }).notNull(),
  timestamp: timestamp('timestamp').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => {
  return {
    symbolTimestampIdx: index('market_quote_cache_symbol_timestamp_idx').on(table.symbol, table.timestamp),
  };
});

// Teams
export const teams = pgTable('teams', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  description: text('description'),
  avatarUrl: varchar('avatar_url', { length: 500 }),
  ownerId: uuid('owner_id').notNull().references(() => users.id),
  settings: jsonb('settings').default({}),
  isPublic: boolean('is_public').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    ownerIdx: index('teams_owner_idx').on(table.ownerId),
  };
});

// Team members
export const teamMembers = pgTable('team_members', {
  id: uuid('id').defaultRandom().primaryKey(),
  teamId: uuid('team_id').notNull().references(() => teams.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  role: varchar('role', { length: 50 }).notNull().default('member'), // owner, admin, member
  joinedAt: timestamp('joined_at').defaultNow().notNull(),
  invitedBy: uuid('invited_by').references(() => users.id),
}, (table) => {
  return {
    teamUserUnique: unique('team_members_unique').on(table.teamId, table.userId),
    teamIdx: index('team_members_team_idx').on(table.teamId),
    userIdx: index('team_members_user_idx').on(table.userId),
  };
});

// Shared folders
export const sharedFolders = pgTable('shared_folders', {
  id: uuid('id').defaultRandom().primaryKey(),
  folderId: uuid('folder_id').notNull().references(() => folders.id, { onDelete: 'cascade' }),
  teamId: uuid('team_id').notNull().references(() => teams.id, { onDelete: 'cascade' }),
  permissions: jsonb('permissions').default({ read: true, write: false, admin: false }),
  sharedBy: uuid('shared_by').notNull().references(() => users.id),
  sharedAt: timestamp('shared_at').defaultNow().notNull(),
}, (table) => {
  return {
    folderTeamUnique: unique('shared_folders_unique').on(table.folderId, table.teamId),
    folderIdx: index('shared_folders_folder_idx').on(table.folderId),
    teamIdx: index('shared_folders_team_idx').on(table.teamId),
  };
});

// Article comments
export const articleComments = pgTable('article_comments', {
  id: uuid('id').defaultRandom().primaryKey(),
  articleId: uuid('article_id').notNull().references(() => articles.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => users.id),
  teamId: uuid('team_id').references(() => teams.id, { onDelete: 'cascade' }),
  parentId: uuid('parent_id'), // Self-reference added later
  content: text('content').notNull(),
  isEdited: boolean('is_edited').default(false).notNull(),
  editedAt: timestamp('edited_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => {
  return {
    articleIdx: index('article_comments_article_idx').on(table.articleId),
    userIdx: index('article_comments_user_idx').on(table.userId),
    teamIdx: index('article_comments_team_idx').on(table.teamId),
    parentIdx: index('article_comments_parent_idx').on(table.parentId),
  };
});

// Article annotations
export const articleAnnotations = pgTable('article_annotations', {
  id: uuid('id').defaultRandom().primaryKey(),
  articleId: uuid('article_id').notNull().references(() => articles.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => users.id),
  teamId: uuid('team_id').references(() => teams.id, { onDelete: 'cascade' }),
  type: varchar('type', { length: 50 }).notNull(), // highlight, note
  content: text('content'),
  selection: jsonb('selection').notNull(), // { start, end, text }
  color: varchar('color', { length: 7 }).default('#FFFF00'),
  isPublic: boolean('is_public').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => {
  return {
    articleIdx: index('article_annotations_article_idx').on(table.articleId),
    userIdx: index('article_annotations_user_idx').on(table.userId),
    teamIdx: index('article_annotations_team_idx').on(table.teamId),
  };
});

// Reading sessions (for presence)
export const readingSessions = pgTable('reading_sessions', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  articleId: uuid('article_id').notNull().references(() => articles.id, { onDelete: 'cascade' }),
  teamId: uuid('team_id').references(() => teams.id, { onDelete: 'cascade' }),
  startedAt: timestamp('started_at').defaultNow().notNull(),
  endedAt: timestamp('ended_at'),
  scrollPosition: integer('scroll_position').default(0),
  readingTime: integer('reading_time').default(0), // seconds
}, (table) => {
  return {
    userArticleIdx: index('reading_sessions_user_article_idx').on(table.userId, table.articleId),
    teamIdx: index('reading_sessions_team_idx').on(table.teamId),
  };
});

// Define relations
export const usersRelations = relations(users, ({ many }) => ({
  oauthProviders: many(oauthProviders),
  devices: many(devices),
  folders: many(folders),
  feeds: many(feeds),
  userArticleStates: many(userArticleStates),
  sharedFoldersCreated: many(sharedFolders),
  readingStats: many(readingStats),
  aiAnalyses: many(aiAnalysis),
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
  aiAnalyses: many(aiAnalysis),
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
  sharedFolders: many(sharedFolders),
}));
