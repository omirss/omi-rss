-- Initial database schema for Omi RSS Server
-- Created: 2024-01-01

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table (extends Serverpod auth)
-- Assumes serverpod_auth already created users table
-- We'll add additional fields if needed

-- User passwords table (for local authentication)
CREATE TABLE user_passwords (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_passwords_user_id ON user_passwords(user_id);

-- Password reset tokens table
CREATE TABLE password_reset_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);
CREATE INDEX idx_password_reset_tokens_expires_at ON password_reset_tokens(expires_at);

-- Add last_login column to serverpod_user_info if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'serverpod_user_info' 
                   AND column_name = 'last_login') THEN
        ALTER TABLE serverpod_user_info ADD COLUMN last_login TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;

-- Folders table
CREATE TABLE folders (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, parent_id, name)
);

CREATE INDEX idx_folders_user_id ON folders(user_id);
CREATE INDEX idx_folders_parent_id ON folders(parent_id);

-- Feeds table
CREATE TABLE feeds (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    favicon TEXT,
    category VARCHAR(100),
    folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    settings JSONB DEFAULT '{}',
    last_fetched_at TIMESTAMP WITH TIME ZONE,
    last_successful_fetch TIMESTAMP WITH TIME ZONE,
    last_error TEXT,
    error_count INTEGER DEFAULT 0,
    is_enabled BOOLEAN DEFAULT true,
    article_count INTEGER DEFAULT 0,
    unread_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, url)
);

CREATE INDEX idx_feeds_user_id ON feeds(user_id);
CREATE INDEX idx_feeds_folder_id ON feeds(folder_id);
CREATE INDEX idx_feeds_is_enabled ON feeds(is_enabled) WHERE deleted_at IS NULL;
CREATE INDEX idx_feeds_url ON feeds(url);

-- Articles table
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    title VARCHAR(1000) NOT NULL,
    url TEXT NOT NULL,
    content TEXT,
    summary TEXT,
    author VARCHAR(255),
    published_at TIMESTAMP WITH TIME ZONE,
    image_url TEXT,
    categories TEXT[],
    guid VARCHAR(500),
    is_read BOOLEAN DEFAULT false,
    is_starred BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(feed_id, guid)
);

CREATE INDEX idx_articles_feed_id ON articles(feed_id);
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_is_read ON articles(is_read);
CREATE INDEX idx_articles_is_starred ON articles(is_starred);
CREATE INDEX idx_articles_url ON articles(url);

-- Feed subscriptions table (many-to-many relationship)
CREATE TABLE feed_subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
    folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    custom_settings JSONB DEFAULT '{}',
    subscribed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_read_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, feed_id)
);

CREATE INDEX idx_feed_subscriptions_user_id ON feed_subscriptions(user_id);
CREATE INDEX idx_feed_subscriptions_feed_id ON feed_subscriptions(feed_id);
CREATE INDEX idx_feed_subscriptions_folder_id ON feed_subscriptions(folder_id);

-- Read history table
CREATE TABLE read_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    read_duration_seconds INTEGER,
    scroll_percentage FLOAT,
    UNIQUE(user_id, article_id)
);

CREATE INDEX idx_read_history_user_id ON read_history(user_id);
CREATE INDEX idx_read_history_article_id ON read_history(article_id);
CREATE INDEX idx_read_history_read_at ON read_history(read_at DESC);

-- Saved articles table
CREATE TABLE saved_articles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    note TEXT,
    tags TEXT[],
    saved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, article_id)
);

CREATE INDEX idx_saved_articles_user_id ON saved_articles(user_id);
CREATE INDEX idx_saved_articles_article_id ON saved_articles(article_id);
CREATE INDEX idx_saved_articles_saved_at ON saved_articles(saved_at DESC);
CREATE INDEX idx_saved_articles_tags ON saved_articles USING GIN(tags);

-- User preferences table
CREATE TABLE user_preferences (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);

-- Analytics events table
CREATE TABLE analytics_events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    event_name VARCHAR(100) NOT NULL,
    properties JSONB DEFAULT '{}',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    session_id VARCHAR(100),
    user_agent TEXT,
    ip_address INET,
    referrer TEXT
);

CREATE INDEX idx_analytics_events_user_id ON analytics_events(user_id);
CREATE INDEX idx_analytics_events_event_name ON analytics_events(event_name);
CREATE INDEX idx_analytics_events_timestamp ON analytics_events(timestamp DESC);
CREATE INDEX idx_analytics_events_session_id ON analytics_events(session_id);

-- Price alerts table (for market feature)
CREATE TABLE price_alerts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES serverpod_user_info(id) ON DELETE CASCADE,
    symbol VARCHAR(20) NOT NULL,
    target_price DECIMAL(20, 8) NOT NULL,
    condition VARCHAR(10) NOT NULL CHECK (condition IN ('above', 'below')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    triggered_at TIMESTAMP WITH TIME ZONE,
    triggered_price DECIMAL(20, 8)
);

CREATE INDEX idx_price_alerts_user_id ON price_alerts(user_id);
CREATE INDEX idx_price_alerts_symbol ON price_alerts(symbol);
CREATE INDEX idx_price_alerts_is_active ON price_alerts(is_active) WHERE is_active = true;

-- Create update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply update timestamp triggers
CREATE TRIGGER update_folders_updated_at BEFORE UPDATE ON folders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_feeds_updated_at BEFORE UPDATE ON feeds
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_articles_updated_at BEFORE UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_preferences_updated_at BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function to update feed article counts
CREATE OR REPLACE FUNCTION update_feed_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE feeds 
        SET article_count = article_count + 1,
            unread_count = unread_count + 1
        WHERE id = NEW.feed_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE feeds 
        SET article_count = article_count - 1,
            unread_count = unread_count - (CASE WHEN OLD.is_read = false THEN 1 ELSE 0 END)
        WHERE id = OLD.feed_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.is_read != NEW.is_read THEN
        UPDATE feeds 
        SET unread_count = unread_count + (CASE WHEN NEW.is_read = false THEN 1 ELSE -1 END)
        WHERE id = NEW.feed_id;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply feed count trigger
CREATE TRIGGER update_feed_counts_trigger
    AFTER INSERT OR DELETE OR UPDATE OF is_read ON articles
    FOR EACH ROW EXECUTE FUNCTION update_feed_counts();

-- Create view for user feed statistics
CREATE VIEW user_feed_stats AS
SELECT 
    fs.user_id,
    fs.feed_id,
    f.title as feed_title,
    f.article_count,
    f.unread_count,
    COUNT(DISTINCT rh.article_id) as read_count,
    COUNT(DISTINCT sa.article_id) as saved_count,
    MAX(rh.read_at) as last_read_at,
    fs.subscribed_at
FROM feed_subscriptions fs
JOIN feeds f ON fs.feed_id = f.id
LEFT JOIN articles a ON f.id = a.feed_id
LEFT JOIN read_history rh ON a.id = rh.article_id AND rh.user_id = fs.user_id
LEFT JOIN saved_articles sa ON a.id = sa.article_id AND sa.user_id = fs.user_id
WHERE f.deleted_at IS NULL
GROUP BY fs.user_id, fs.feed_id, f.title, f.article_count, f.unread_count, fs.subscribed_at;

-- Add comments for documentation
COMMENT ON TABLE folders IS 'User-created folders for organizing feeds';
COMMENT ON TABLE feeds IS 'RSS/Atom feed sources';
COMMENT ON TABLE articles IS 'Articles fetched from feeds';
COMMENT ON TABLE feed_subscriptions IS 'User subscriptions to feeds';
COMMENT ON TABLE read_history IS 'Track which articles users have read';
COMMENT ON TABLE saved_articles IS 'Articles saved by users for later';
COMMENT ON TABLE user_preferences IS 'User-specific settings and preferences';
COMMENT ON TABLE analytics_events IS 'User activity tracking for analytics';
COMMENT ON TABLE price_alerts IS 'Price alerts for market data feature';