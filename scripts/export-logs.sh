#!/usr/bin/env bash
# Daily copy of the Stalwart container log (docker json-file is lost when the
# container is recreated). Writes yesterday's UTC day; keeps KEEP_DAYS days.
#   export-logs.sh [YYYY-MM-DD]
set -euo pipefail
DIR=${LOG_DIR:-/opt/mail/logs/stalwart}
KEEP_DAYS=${KEEP_DAYS:-30}
DAY=${1:-$(date -u -d yesterday +%F)}
NEXT=$(date -u -d "$DAY +1 day" +%F)
mkdir -p "$DIR"
OUT="$DIR/stalwart-$DAY.log.gz"
docker logs --since "${DAY}T00:00:00Z" --until "${NEXT}T00:00:00Z" stalwart 2>&1 | gzip -9 > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
chmod 600 "$OUT"
find "$DIR" -name 'stalwart-*.log.gz' -mtime +"$KEEP_DAYS" -delete
echo "$(date -u +%FT%TZ) logs exported: $OUT ($(zcat "$OUT" | wc -l) lines)"
