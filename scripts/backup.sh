#!/usr/bin/env bash
# Daily backup of the mail stack volumes (Stalwart RocksDB + Bulwark data).
# Stalwart is stopped for a few seconds so RocksDB is copied consistently;
# senders simply retry, no mail is lost.
# Cron (root): 45 4 * * * /opt/mail/scripts/backup.sh >> /opt/mail/logs/backup.log 2>&1
set -euo pipefail

DEST=/opt/mail/backups
KEEP_DAYS=${KEEP_DAYS:-7}
TS=$(date +%Y%m%d-%H%M%S)
cd /opt/mail
mkdir -p "$DEST"

echo "$(date -Is) backup start"
docker compose stop stalwart >/dev/null
trap 'docker compose start stalwart >/dev/null' EXIT

docker run --rm \
  -v mail_stalwart-etc:/src/stalwart-etc:ro \
  -v mail_stalwart-data:/src/stalwart-data:ro \
  -v mail_bulwark-settings:/src/bulwark-settings:ro \
  -v mail_bulwark-admin:/src/bulwark-admin:ro \
  -v "$DEST":/dest \
  alpine tar czf "/dest/mail-$TS.tar.gz" -C /src .

docker compose start stalwart >/dev/null
trap - EXIT
cp .env "$DEST/env-$TS" && chmod 600 "$DEST/env-$TS" "$DEST/mail-$TS.tar.gz"

find "$DEST" -name 'mail-*.tar.gz' -mtime +"$KEEP_DAYS" -delete
find "$DEST" -name 'env-*' -mtime +"$KEEP_DAYS" -delete
echo "$(date -Is) backup done: $(du -h "$DEST/mail-$TS.tar.gz" | cut -f1)"
