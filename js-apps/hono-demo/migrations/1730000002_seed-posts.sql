-- Migration: Seed initial posts
-- Created: 2025-11-03

-- Only insert if table is empty
INSERT INTO posts (title, body)
SELECT * FROM (VALUES
  ('Good Morning', 'Let us eat breakfast'),
  ('Good Afternoon', 'Let us eat Lunch'),
  ('Good Evening', 'Let us eat Dinner'),
  ('Good Night', 'Let us drink Beer'),
  ('こんにちは', '昼からビールを飲みます')
) AS v(title, body)
WHERE NOT EXISTS (SELECT 1 FROM posts LIMIT 1);
