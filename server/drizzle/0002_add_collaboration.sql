-- Add collaboration sessions table
CREATE TABLE IF NOT EXISTS collaboration_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id UUID NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL CHECK (type IN ('reading', 'annotation', 'discussion')),
  article_id UUID REFERENCES articles(id) ON DELETE CASCADE,
  participants JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN NOT NULL DEFAULT true,
  started_at TIMESTAMP NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX collab_sessions_folder_idx ON collaboration_sessions(folder_id);
CREATE INDEX collab_sessions_host_idx ON collaboration_sessions(host_user_id);
CREATE INDEX collab_sessions_active_idx ON collaboration_sessions(is_active);
CREATE INDEX collab_sessions_article_idx ON collaboration_sessions(article_id);

-- Add collaboration annotations table
CREATE TABLE IF NOT EXISTS collaboration_annotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES collaboration_sessions(id) ON DELETE CASCADE,
  article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL CHECK (type IN ('highlight', 'comment', 'reaction')),
  content TEXT,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX collab_annotations_session_idx ON collaboration_annotations(session_id);
CREATE INDEX collab_annotations_article_idx ON collaboration_annotations(article_id);
CREATE INDEX collab_annotations_user_idx ON collaboration_annotations(user_id);

-- Add collaboration presence table
CREATE TABLE IF NOT EXISTS collaboration_presence (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  folder_id UUID NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('online', 'idle', 'offline')),
  current_article_id UUID REFERENCES articles(id) ON DELETE SET NULL,
  last_activity TIMESTAMP NOT NULL DEFAULT NOW(),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, folder_id)
);

CREATE INDEX collab_presence_folder_idx ON collaboration_presence(folder_id);
CREATE INDEX collab_presence_status_idx ON collaboration_presence(status);

-- Add profile_image column to users if it doesn't exist
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_image TEXT;

-- Add name column to users if it doesn't exist  
ALTER TABLE users ADD COLUMN IF NOT EXISTS name VARCHAR(255) GENERATED ALWAYS AS (
  COALESCE(first_name || ' ' || last_name, username)
) STORED;