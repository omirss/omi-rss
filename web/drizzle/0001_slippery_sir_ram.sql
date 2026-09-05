DROP TABLE "oauth_providers";--> statement-breakpoint
ALTER TABLE "user_article_states" DROP COLUMN IF EXISTS "scroll_position";--> statement-breakpoint
ALTER TABLE "user_article_states" DROP COLUMN IF EXISTS "notes";--> statement-breakpoint
ALTER TABLE "user_article_states" DROP COLUMN IF EXISTS "highlights";