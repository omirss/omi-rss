DO $$
DECLARE
  duplicate_groups integer;
BEGIN
  SELECT COUNT(*) INTO duplicate_groups FROM (
    SELECT 1 FROM feeds GROUP BY user_id, url HAVING COUNT(*) > 1
  ) duplicates;
  IF duplicate_groups > 0 THEN
    RAISE EXCEPTION 'feeds_owner_url_unique: % group(s) of duplicate (user_id, url) rows exist — resolve them manually before migrating', duplicate_groups;
  END IF;
END
$$;

CREATE UNIQUE INDEX "feeds_owner_url_unique" ON "feeds" USING btree ("user_id","url");

-- Folder-parent cycle guard (audit F042): serializes parent changes per
-- user with a transaction-scoped advisory lock, then walks the ancestry to
-- reject cycles at the DB level (the route pre-check alone is TOCTOU-racy).
CREATE OR REPLACE FUNCTION omi_check_folder_parent() RETURNS trigger AS $$
DECLARE
  current_parent uuid;
  node uuid;
  depth integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text, 719));
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.parent_id = NEW.id THEN
    RAISE EXCEPTION 'folder cannot be its own parent';
  END IF;
  node := NEW.parent_id;
  FOR depth IN 1..64 LOOP
    SELECT parent_id INTO current_parent FROM folders WHERE id = node AND user_id = NEW.user_id;
    IF NOT FOUND THEN RETURN NEW; END IF;
    IF current_parent IS NULL THEN RETURN NEW; END IF;
    IF current_parent = NEW.id THEN
      RAISE EXCEPTION 'folder cycle detected';
    END IF;
    node := current_parent;
  END LOOP;
  RAISE EXCEPTION 'folder hierarchy deeper than 64 levels';
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS omi_check_folder_parent ON folders;
CREATE TRIGGER omi_check_folder_parent BEFORE INSERT OR UPDATE OF parent_id ON folders
FOR EACH ROW EXECUTE FUNCTION omi_check_folder_parent();
