# Status (Uptime Kuma)

Status monitoring page powered by [Uptime Kuma](https://github.com/louislam/uptime-kuma).

## Local Development

```bash
# Start service
mr dev-status
```

Dashboard: http://localhost:9006

On first run, you'll be prompted to create an admin account.

## Data Storage

SQLite database is stored in Docker volume:
- Local: `sqlite_status_data` volume
- Server: `sqlite_status_data` or `sqlite_status--<branch>_data` volume

Data location: `/data/docker/volumes/<volume-name>/_data/kuma.db`

Volume 命名规范：`sqlite_<app>_data`，以便备份脚本自动发现。

## Deployment

```bash
mr build-status
mr deploy-status
```

## Backup

SQLite database can be backed up via:
```bash
# On server, copy from volume
docker cp $(docker ps -qf name=status):/app/data/kuma.db ./kuma.db.bak
```
