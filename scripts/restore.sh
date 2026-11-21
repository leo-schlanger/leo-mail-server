#!/usr/bin/env bash
# Restore the mail volumes from a backup made by backup.sh.
#   /opt/mail/scripts/restore.sh /opt/mail/backups/mail-YYYYmmdd-HHMMSS.tar.gz
# On a brand-new server: run install.sh first, then this.
# Every top-level folder in the archive is one volume (mail_<folder>).
set -euo pipefail
ARCHIVE=$(realpath "${1:?usage: restore.sh <mail-*.tar.gz>}")
ALPINE=alpine:3.22   # same tag as backup.sh
cd /opt/mail

vols=$(tar tzf "$ARCHIVE" | sed -n 's|^\./\([^/]*\)/.*|\1|p' | sort -u)
[ -n "$vols" ] || { echo "ABORT: no volume folders in $ARCHIVE" >&2; exit 1; }
echo "Volumes in the backup: $(tr '\n' ' ' <<<"$vols")"
read -r -p "This OVERWRITES the current mailboxes with $ARCHIVE. Type 'yes': " ok
[ "$ok" = "yes" ] || exit 1

docker compose down
mounts=()
for v in $vols; do
  docker volume create --label com.docker.compose.project=mail --label com.docker.compose.volume="$v" "mail_$v" >/dev/null
  mounts+=(-v "mail_$v:/dst/$v")
done
docker run --rm "${mounts[@]}" \
  -v "$(dirname "$ARCHIVE")":/backup:ro \
  "$ALPINE" sh -c "rm -rf /dst/*/* /dst/*/.[!.]* && tar xzf /backup/$(basename "$ARCHIVE") -C /dst"
docker compose up -d
echo "restored. check: docker compose logs -f stalwart"
