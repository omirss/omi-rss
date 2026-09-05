ALTER TABLE "articles" ADD COLUMN "content_extracted" text;--> statement-breakpoint
ALTER TABLE "feeds" ADD COLUMN "full_text_enabled" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "feeds" ADD COLUMN "source_type" varchar(20) DEFAULT 'rss' NOT NULL;--> statement-breakpoint
ALTER TABLE "feeds" ADD COLUMN "page_url" text;--> statement-breakpoint
ALTER TABLE "feeds" ADD COLUMN "page_selector" text;