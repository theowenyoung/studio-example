# Redis with Production Backup

Simple, reliable Redis setup with automated backups.

## Features

- **Redis Server**: Redis 7.4 Alpine with production configuration
- **Automated Backups**: Daily backups with configurable retention
- **Health Checks**: Built-in monitoring for both services
- **Compression**: Gzip compression for backup files
- **Cron Scheduling**: Flexible backup scheduling

## Quick Start

1. Copy environment configuration:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` file:
   ```bash
   # Change default password
   COMMON_REDIS_PASSWORD=your_secure_password_here
   ```

3. Start services:
   ```bash
   docker compose up -d
   ```

## Configuration

### Environment Variables
- `COMMON_REDIS_PASSWORD`: Redis authentication password
- `BACKUP_KEEP_DAYS`: Days to keep backups (default: 7)
- `SCHEDULE`: Cron expression (default: 0 2 * * * = 2 AM daily)

## Manual Operations

### Manual Backup
```bash
docker compose exec redis-backup /usr/local/bin/backup.sh run
```

### View Logs
```bash
docker compose logs redis-backup
```

### Access Redis
```bash
docker compose exec redis redis-cli -a your_password
```

### Check Backups
```bash
ls -la .local/backups/
```

## File Structure
```
infra-apps/redis/
├── docker-compose.yml    # Main configuration
├── .env                 # Environment variables
├── .env.example         # Template
├── redis.conf           # Redis config
├── backup.sh            # Backup script
└── .local/backups/      # Backup storage
```