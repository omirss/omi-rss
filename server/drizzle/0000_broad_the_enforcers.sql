CREATE TABLE IF NOT EXISTS "articles" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"feed_id" uuid NOT NULL,
	"guid" text NOT NULL,
	"url" text NOT NULL,
	"title" text NOT NULL,
	"author" varchar(255),
	"content" text,
	"summary" text,
	"image_url" text,
	"published_at" timestamp,
	"categories" jsonb DEFAULT '[]'::jsonb,
	"enclosures" jsonb DEFAULT '[]'::jsonb,
	"metadata" jsonb DEFAULT '{}'::jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "feeds" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"folder_id" uuid,
	"url" text NOT NULL,
	"title" varchar(500) NOT NULL,
	"description" text,
	"site_url" text,
	"favicon" text,
	"image_url" text,
	"custom_title" varchar(500),
	"update_interval" integer DEFAULT 30,
	"last_fetched_at" timestamp,
	"last_fetch_error" text,
	"error_count" integer DEFAULT 0,
	"is_active" boolean DEFAULT true NOT NULL,
	"settings" jsonb DEFAULT '{}'::jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "folders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	"parent_id" uuid,
	"color" varchar(7),
	"icon" varchar(50),
	"position" integer DEFAULT 0,
	"is_expanded" boolean DEFAULT true,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"type" varchar(50) NOT NULL,
	"title" varchar(255) NOT NULL,
	"body" text,
	"data" jsonb DEFAULT '{}'::jsonb,
	"channels" jsonb DEFAULT '[]'::jsonb,
	"status" varchar(50) DEFAULT 'pending' NOT NULL,
	"read_at" timestamp,
	"sent_at" timestamp,
	"failed_at" timestamp,
	"error" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "oauth_providers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"provider" varchar(50) NOT NULL,
	"provider_id" varchar(255) NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"expires_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "reading_stats" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"date" timestamp NOT NULL,
	"articles_read" integer DEFAULT 0 NOT NULL,
	"reading_time" integer DEFAULT 0 NOT NULL,
	"words_read" integer DEFAULT 0 NOT NULL,
	"feeds_visited" jsonb DEFAULT '[]'::jsonb,
	"categories" jsonb DEFAULT '{}'::jsonb,
	"hourly_distribution" jsonb DEFAULT '{}'::jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "user_article_states" (
	"user_id" uuid NOT NULL,
	"article_id" uuid NOT NULL,
	"is_read" boolean DEFAULT false NOT NULL,
	"is_starred" boolean DEFAULT false NOT NULL,
	"read_at" timestamp,
	"starred_at" timestamp,
	"reading_time" integer,
	"scroll_position" integer DEFAULT 0,
	"notes" text,
	"highlights" jsonb DEFAULT '[]'::jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "user_article_states_user_id_article_id_pk" PRIMARY KEY("user_id","article_id")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" varchar(255) NOT NULL,
	"username" varchar(100) NOT NULL,
	"password_hash" varchar(255),
	"first_name" varchar(100),
	"last_name" varchar(100),
	"avatar_url" text,
	"role" varchar(50) DEFAULT 'user' NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"email_verification_token" varchar(255),
	"password_reset_token" varchar(255),
	"password_reset_expires" timestamp,
	"last_login_at" timestamp,
	"settings" jsonb DEFAULT '{}'::jsonb,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email"),
	CONSTRAINT "users_username_unique" UNIQUE("username")
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "articles_feed_idx" ON "articles" ("feed_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "articles_guid_idx" ON "articles" ("feed_id","guid");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "articles_published_idx" ON "articles" ("published_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "feeds_user_idx" ON "feeds" ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "feeds_folder_idx" ON "feeds" ("folder_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "feeds_url_idx" ON "feeds" ("url");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "folders_user_idx" ON "folders" ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "folders_parent_idx" ON "folders" ("parent_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "notifications_user_idx" ON "notifications" ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "notifications_status_idx" ON "notifications" ("status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "notifications_type_idx" ON "notifications" ("type");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "oauth_user_provider_idx" ON "oauth_providers" ("user_id","provider");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "oauth_provider_id_idx" ON "oauth_providers" ("provider","provider_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "reading_stats_user_date_idx" ON "reading_stats" ("user_id","date");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "user_article_states_user_idx" ON "user_article_states" ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "user_article_states_article_idx" ON "user_article_states" ("article_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "user_article_states_read_idx" ON "user_article_states" ("is_read");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "user_article_states_starred_idx" ON "user_article_states" ("is_starred");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "users_email_idx" ON "users" ("email");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "users_username_idx" ON "users" ("username");--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "articles" ADD CONSTRAINT "articles_feed_id_feeds_id_fk" FOREIGN KEY ("feed_id") REFERENCES "feeds"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "feeds" ADD CONSTRAINT "feeds_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "feeds" ADD CONSTRAINT "feeds_folder_id_folders_id_fk" FOREIGN KEY ("folder_id") REFERENCES "folders"("id") ON DELETE set null ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "folders" ADD CONSTRAINT "folders_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "folders" ADD CONSTRAINT "folders_parent_id_folders_id_fk" FOREIGN KEY ("parent_id") REFERENCES "folders"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "oauth_providers" ADD CONSTRAINT "oauth_providers_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "reading_stats" ADD CONSTRAINT "reading_stats_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "user_article_states" ADD CONSTRAINT "user_article_states_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "user_article_states" ADD CONSTRAINT "user_article_states_article_id_articles_id_fk" FOREIGN KEY ("article_id") REFERENCES "articles"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
