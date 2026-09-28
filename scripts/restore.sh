#!/usr/bin/env bash
# Restore the mail volumes from a backup made by backup.sh.
#   /opt/mail/scripts/restore.sh /opt/mail/backups/mail-YYYYmmdd-HHMMSS.tar.gz
# On a brand-new server: run install.sh first (it creates the volumes), then this.
set -euo pipefail
ARCHIVE=$(realpath "${1:?usage: restore.sh <mail-*.tar.gz>}")
cd /opt/mail

read -r -p "This OVERWRITES the current mailboxes with $ARCHIVE. Type 'yes': " ok
[ "$ok" = "yes" ] || exit 1

docker compose down
for v in stalwart-etc stalwart-data bulwark-settings bulwark-admin; do docker volume create "mail_$v" >/dev/null; done
docker run --rm \
  -v mail_stalwart-etc:/dst/stalwart-etc \
  -v mail_stalwart-data:/dst/stalwart-data \
  -v mail_bulwark-settings:/dst/bulwark-settings \
  -v mail_bulwark-admin:/dst/bulwark-admin \
  -v "$(dirname "$ARCHIVE")":/backup:ro \
  alpine sh -c "rm -rf /dst/*/* && tar xzf /backup/$(basename "$ARCHIVE") -C /dst"
docker compose up -d
echo "restored. check: docker compose logs -f stalwart"
