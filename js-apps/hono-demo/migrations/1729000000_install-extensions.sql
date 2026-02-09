-- Migration: Install PostgreSQL Extensions
-- Created: 2025-11-25
-- Description: Install essential extensions needed by the application
--              Modern PostgreSQL 18 best practices - minimal and necessary only
-- ==========================================
-- Full-text search & fuzzy matching
-- ==========================================
-- Provides trigram matching for fuzzy text search
-- Used for: searching posts by title/body, user names, autocomplete
-- Enables efficient LIKE/ILIKE queries with GIN indexes
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ==========================================
-- Case-insensitive text
-- ==========================================
-- Provides case-insensitive text type
-- Used for: email addresses, usernames, tags
-- Example: 'User@Example.COM' = 'user@example.com'
CREATE EXTENSION IF NOT EXISTS citext;

-- ==========================================
-- UUID generation (Built-in)
-- ==========================================
-- No extension needed! PostgreSQL 13+ has gen_random_uuid() built-in
-- Usage: id UUID PRIMARY KEY DEFAULT gen_random_uuid()

-- ==========================================
-- Notes for adding more extensions:
-- ==========================================
-- Common extensions (add only when needed):
--   - pgcrypto         (encryption, hashing, advanced crypto)
--   - ltree            (hierarchical tree structures, categories)
--   - btree_gist       (exclusion constraints, range types)
--   - unaccent         (remove accents for search: café -> cafe)
--
-- Deprecated/Unnecessary in modern PostgreSQL:
--   - uuid-ossp        ❌ Use gen_random_uuid() instead
--   - hstore           ❌ Use JSONB instead
--   - btree_gin        ❌ Rarely needed, add only if specific use case
--
-- Extensions requiring SUPERUSER (manual installation):
--   - postgis          (geographic/spatial data)
--   - timescaledb      (time-series data)
--   - pg_stat_statements (query performance monitoring)
--   - postgres_fdw     (foreign data wrapper for other PostgreSQL)
--
-- If you need a SUPERUSER extension:
-- 1. Document the specific use case
-- 2. Add installation command in README
-- 3. Run: docker exec postgres psql -U postgres -d your_db -c "CREATE EXTENSION xxx;"
-- ==========================================

-- Verify extensions are installed
DO $$
DECLARE
  ext_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO ext_count
  FROM pg_extension
  WHERE extname IN ('pg_trgm', 'citext');
  
  RAISE NOTICE 'Installed extensions: %/2', ext_count;
  
  IF ext_count < 2 THEN
    RAISE WARNING 'Expected 2 extensions, found %. Some extensions may not be installed.', ext_count;
  ELSE
    RAISE NOTICE '✓ All essential extensions installed successfully';
  END IF;
END $$;
