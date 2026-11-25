#!/usr/bin/env bash
# Daily backup of every volume of the mail stack (Stalwart RocksDB + data of
# both Bulwark webmails), found by the compose project label, so a volume
# added to docker-compose.yml is backed up without editing this script.
# Stalwart is stopped for a few seconds so RocksDB is copied consistently;
# senders simply retry, no mail is lost.
# Cron (root): 45 4 * * * /opt/mail/scripts/backup.sh >> /opt/mail/logs/backup.log 2>&1
set -euo pipefail

DEST=/opt/mail/backups
KEEP_DAYS=${KEEP_DAYS:-7}
ALPINE=alpine:3.22   # pinned; same tag in restore.sh
TS=$(date +%Y%m%d-%H%M%S)
cd /opt/mail
mkdir -p "$DEST"

echo "$(date -Is) backup start"
# Pull before stopping Stalwart, so a missing image (host prune) or a registry
# outage never extends the downtime.
docker image inspect "$ALPINE" >/dev/null 2>&1 || docker pull -q "$ALPINE" >/dev/null

mounts=()
for v in $(docker volume ls -q --filter label=com.docker.compose.project=mail); do
  mounts+=(-v "$v:/src/${v#mail_}:ro")
done
# v1 volumes were created before compose owned them, so they have no project label.
for v in mail_stalwart-v1-etc mail_stalwart-v1-data mail_migrate-state; do
  docker volume inspect "$v" >/dev/null 2>&1 || continue
  mounts+=(-v "$v:/src/${v#mail_}:ro")
done
[ ${#mounts[@]} -gt 0 ] || { echo "ABORT: no mail_* volumes found" >&2; exit 1; }

docker compose stop stalwart >/dev/null
trap 'docker compose start stalwart >/dev/null' EXIT

docker run --rm "${mounts[@]}" -v "$DEST":/dest \
  "$ALPINE" tar czf "/dest/mail-$TS.tar.gz" -C /src .

docker compose start stalwart >/dev/null
trap - EXIT
cp .env "$DEST/env-$TS" && chmod 600 "$DEST/env-$TS" "$DEST/mail-$TS.tar.gz"

find "$DEST" -name 'mail-*.tar.gz' -mtime +"$KEEP_DAYS" -delete
find "$DEST" -name 'env-*' -mtime +"$KEEP_DAYS" -delete
echo "$(date -Is) backup done: $(du -h "$DEST/mail-$TS.tar.gz" | cut -f1), $(( ${#mounts[@]} / 2 )) volumes"
