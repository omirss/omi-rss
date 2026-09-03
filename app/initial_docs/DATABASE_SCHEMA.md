# Database Schema Documentation

## Overview

The RSS Glassmorphism Reader uses two databases:
1. **Local SQLite** (via Drift) - Client-side storage
2. **PostgreSQL** - Server-side storage

## Local Database (SQLite)

### feeds
Stores RSS/Atom/JSON feed subscriptions.

```sql
CREATE TABLE feeds (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  description TEXT,
  site_url TEXT,
  icon_url TEXT,
  type TEXT NOT NULL CHECK (type IN ('rss', 'atom', 'json')),
  category_id TEXT REFERENCES categories(id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  update_frequency INTEGER NOT NULL DEFAULT 3600,
  last_fetched DATETIME,
  etag TEXT,
  last_modified TEXT,
  custom_title TEXT,
  custom_icon TEXT,
  notification_enabled BOOLEAN NOT NULL DEFAULT false,
  full_text_enabled BOOLEAN NOT NULL DEFAULT false,
  bypass_enabled BOOLEAN NOT NULL DEFAULT false,
  user_agent TEXT,
  custom_headers TEXT, -- JSON
  successful_fetches INTEGER NOT NULL DEFAULT 0,
  failed_fetches INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  last_error_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feeds_category ON feeds(category_id);
CREATE INDEX idx_feeds_active ON feeds(is_active);
CREATE INDEX idx_feeds_last_fetched ON feeds(last_fetched);
```

### articles
Stores feed articles/entries.

```sql
CREATE TABLE articles (
  id TEXT PRIMARY KEY,
  feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  guid TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  content TEXT,
  full_content TEXT,
  url TEXT NOT NULL,
  author TEXT,
  published_at DATETIME,
  updated_at DATETIME,
  is_read BOOLEAN NOT NULL DEFAULT false,
  is_starred BOOLEAN NOT NULL DEFAULT false,
  read_at DATETIME,
  starred_at DATETIME,
  reading_time INTEGER, -- minutes
  word_count INTEGER,
  language TEXT,
  tags TEXT, -- Comma-separated
  enclosures TEXT, -- JSON array
  
  -- AI fields
  ai_summary TEXT,
  ai_tags TEXT, -- Comma-separated
  perspectives_json TEXT, -- JSON object
  sentiment_score REAL,
  bias_score REAL,
  fact_check_json TEXT, -- JSON object
  
  -- Extraction fields
  full_content_available BOOLEAN NOT NULL DEFAULT false,
  full_content_fetched_at DATETIME,
  main_image_url TEXT,
  extracted_videos_json TEXT, -- JSON array
  extracted_links_json TEXT, -- JSON array
  
  -- Market data correlation
  mentioned_symbols TEXT, -- Comma-separated stock symbols
  market_data_json TEXT, -- JSON object
  
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(feed_id, guid)
);

CREATE INDEX idx_articles_feed ON articles(feed_id);
CREATE INDEX idx_articles_published ON articles(published_at DESC);
CREATE INDEX idx_articles_unread ON articles(is_read, published_at DESC);
CREATE INDEX idx_articles_starred ON articles(is_starred, published_at DESC);
CREATE INDEX idx_articles_search ON articles(title, content);
```

### categories
Organizes feeds into categories.

```sql
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_id TEXT REFERENCES categories(id),
  color TEXT,
  icon TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_expanded BOOLEAN NOT NULL DEFAULT true,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_categories_parent ON categories(parent_id);
CREATE INDEX idx_categories_sort ON categories(sort_order);
```

### settings
Key-value storage for app settings.

```sql
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### read_history
Tracks article reading history.

```sql
CREATE TABLE read_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at DATETIME,
  duration_seconds INTEGER,
  scroll_depth REAL, -- 0.0 to 1.0
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_read_history_article ON read_history(article_id);
CREATE INDEX idx_read_history_date ON read_history(started_at DESC);
```

### sync_queue
Offline sync queue for changes.

```sql
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL, -- 'feed', 'article', 'category'
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL, -- 'create', 'update', 'delete'
  data TEXT NOT NULL, -- JSON payload
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sync_queue_created ON sync_queue(created_at);
```

### generation_rules
Custom feed generation rules.

```sql
CREATE TABLE generation_rules (
  id TEXT PRIMARY KEY,
  site TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  patterns_json TEXT NOT NULL, -- JSON array
  selectors_json TEXT NOT NULL, -- JSON object
  transforms_json TEXT NOT NULL, -- JSON array
  javascript_required BOOLEAN NOT NULL DEFAULT false,
  rate_limit INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  success_count INTEGER NOT NULL DEFAULT 0,
  failure_count INTEGER NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_generation_rules_site ON generation_rules(site);
```

### bypass_rules
Site-specific paywall bypass rules.

```sql
CREATE TABLE bypass_rules (
  id TEXT PRIMARY KEY,
  domain TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  methods_json TEXT NOT NULL, -- JSON array of methods
  selectors_json TEXT NOT NULL, -- JSON object
  success_rate REAL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_success_at DATETIME,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_bypass_rules_domain ON bypass_rules(domain);
```

## Server Database (PostgreSQL)

### users
User accounts.

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(100),
  avatar_url TEXT,
  role VARCHAR(50) NOT NULL DEFAULT 'user',
  is_active BOOLEAN NOT NULL DEFAULT true,
  email_verified BOOLEAN NOT NULL DEFAULT false,
  last_login_at TIMESTAMP,
  settings JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
```

### user_feeds
User's feed subscriptions (server sync).

```sql
CREATE TABLE user_feeds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_url TEXT NOT NULL,
  custom_title TEXT,
  category_id UUID REFERENCES user_categories(id),
  settings JSONB NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_synced_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, feed_url)
);

CREATE INDEX idx_user_feeds_user ON user_feeds(user_id);
```

### user_categories
User's categories (server sync).

```sql
CREATE TABLE user_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  parent_id UUID REFERENCES user_categories(id),
  color VARCHAR(7),
  icon VARCHAR(50),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_categories_user ON user_categories(user_id);
```

### article_states
User's article read/star states (server sync).

```sql
CREATE TABLE article_states (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_guid TEXT NOT NULL,
  feed_url TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  is_starred BOOLEAN NOT NULL DEFAULT false,
  read_at TIMESTAMP,
  starred_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, article_guid, feed_url)
);

CREATE INDEX idx_article_states_user ON article_states(user_id);
CREATE INDEX idx_article_states_guid ON article_states(article_guid);
```

### feed_cache
Global feed cache for performance.

```sql
CREATE TABLE feed_cache (
  url TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  type VARCHAR(10),
  last_fetched_at TIMESTAMP,
  etag TEXT,
  last_modified TEXT,
  content TEXT, -- Compressed feed XML/JSON
  articles_json JSONB, -- Latest articles
  metadata JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feed_cache_updated ON feed_cache(updated_at);
```

### generated_feeds
Server-side generated feeds.

```sql
CREATE TABLE generated_feeds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_url TEXT NOT NULL,
  feed_url TEXT UNIQUE NOT NULL,
  rule_id UUID,
  title TEXT,
  description TEXT,
  format VARCHAR(10) NOT NULL DEFAULT 'rss',
  is_public BOOLEAN NOT NULL DEFAULT false,
  access_count INTEGER NOT NULL DEFAULT 0,
  last_generated_at TIMESTAMP,
  expires_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_generated_feeds_source ON generated_feeds(source_url);
CREATE INDEX idx_generated_feeds_expires ON generated_feeds(expires_at);
```

### ai_analysis_cache
Cache AI analysis results.

```sql
CREATE TABLE ai_analysis_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_hash VARCHAR(64) NOT NULL,
  analysis_type VARCHAR(50) NOT NULL,
  provider VARCHAR(50) NOT NULL,
  result JSONB NOT NULL,
  tokens_used INTEGER,
  cost_cents INTEGER,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(content_hash, analysis_type, provider)
);

CREATE INDEX idx_ai_cache_hash ON ai_analysis_cache(content_hash);
CREATE INDEX idx_ai_cache_created ON ai_analysis_cache(created_at);
```

### market_data
Real-time market data cache.

```sql
CREATE TABLE market_data (
  symbol VARCHAR(10) NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  volume BIGINT,
  high DECIMAL(10, 2),
  low DECIMAL(10, 2),
  open DECIMAL(10, 2),
  close DECIMAL(10, 2),
  change DECIMAL(10, 2),
  change_percent DECIMAL(5, 2),
  PRIMARY KEY (symbol, timestamp)
);

CREATE INDEX idx_market_data_symbol ON market_data(symbol, timestamp DESC);
```

### user_sessions
Active user sessions.

```sql
CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(64) UNIQUE NOT NULL,
  device_id VARCHAR(100),
  device_name TEXT,
  ip_address INET,
  user_agent TEXT,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_active_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);
```

## Database Migrations

### Version Control
All schema changes tracked in `migrations/` directory:
- `001_initial_schema.sql`
- `002_add_ai_fields.sql`
- `003_add_market_data.sql`
- etc.

### Migration Strategy
1. Always backwards compatible
2. Add columns as nullable first
3. Populate data
4. Add constraints after
5. Never drop columns in production

## Indexes Strategy

### Read Performance
- Index all foreign keys
- Index common WHERE clauses
- Index ORDER BY columns
- Partial indexes for boolean filters

### Write Performance
- Minimal indexes on high-write tables
- Batch inserts for sync operations
- Async index creation

## Data Retention

### Local Database
- Articles: Keep 6 months or 10,000 per feed
- Read history: Keep 3 months
- Sync queue: Delete after successful sync

### Server Database
- User data: Keep indefinitely
- Feed cache: Keep 7 days
- AI cache: Keep 30 days
- Market data: Keep 1 year detailed, 5 years daily

## Backup Strategy

### Local
- Auto-backup on app upgrade
- Export to cloud storage
- Maximum 5 backups kept

### Server
- Daily automated backups
- Point-in-time recovery enabled
- Cross-region replication
- 30-day retention