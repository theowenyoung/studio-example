// node-pg-migrate configuration
// https://salsita.github.io/node-pg-migrate/#/

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Load .env file manually
const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = join(__dirname, '.env');

try {
  const envContent = readFileSync(envPath, 'utf-8');
  envContent.split('\n').forEach(line => {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const [key, ...valueParts] = trimmed.split('=');
      if (key && valueParts.length > 0) {
        process.env[key.trim()] = valueParts.join('=').trim();
      }
    }
  });
} catch (err) {
  // .env file not found, use environment variables
}



export default {
  // Database connection string (from environment variable)
  databaseUrl: process.env.DATABASE_URL,

  // Directory where migration files are stored
  dir: 'migrations',

  // Migration table name
  migrationsTable: 'pgmigrations',

  // Create migration files with .sql extension
  ignorePattern: '.*\\.map',

  // Direction (default: up)
  direction: 'up',

  // Count (number of migrations to run)
  count: Infinity,

  // Timestamp format for migration files
  timestampFormat: 'unix',

  // Log SQL queries
  verbose: true,

  // Check ordering of migrations
  checkOrder: true,

  // Allow camelCase in SQL
  decamelize: false
}
