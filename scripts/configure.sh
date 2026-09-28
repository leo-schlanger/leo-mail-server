#!/usr/bin/env bash
# First-time Stalwart configuration, fully from the CLI (no web wizard).
#
#   configure.sh bootstrap   # 1. answer the setup wizard (Bootstrap object)
#   configure.sh apply       # 2. load stalwart/plan.ndjson (listener, TLS, CORS)
#   configure.sh user NAME   # 3. create NAME@leoschlanger.com (asks for password)
#   configure.sh dns         # 4. print the DNS zone to publish
#   configure.sh cli ARGS    #    run any stalwart-cli command
#
# All steps talk to Stalwart on http://127.0.0.1:8480 with the recovery admin
# from .env. Fallback for step 1: open an SSH tunnel
#   ssh -L 8480:127.0.0.1:8480 personal-vps
# and use the wizard at http://localhost:8480/admin
set -euo pipefail
cd /opt/mail
DOMAIN=leoschlanger.com
HOST=mail.leoschlanger.com

# shellcheck disable=SC1091
set -a; . ./.env; set +a
ADMIN_USER=${STALWART_RECOVERY_ADMIN%%:*}
ADMIN_PASS=${STALWART_RECOVERY_ADMIN#*:}

cli() {
  docker run --rm -i --network host \
    -e XDG_CACHE_HOME=/tmp \
    -v "$PWD/stalwart":/work:ro -w /work \
    -e STALWART_URL=http://127.0.0.1:8480 \
    -e STALWART_USER="$ADMIN_USER" -e STALWART_PASSWORD="$ADMIN_PASS" \
    stalwartlabs/cli "$@"
}

case "${1:-}" in
  bootstrap)
    cli update Bootstrap \
      --field serverHostname=$HOST \
      --field defaultDomain=$DOMAIN \
      --field requestTlsCertificate=false \
      --field generateDkimKeys=true \
      --field 'tracer={"@type":"Stdout"}'
    echo "Bootstrap submitted. Restarting Stalwart into normal mode..."
    sleep 3; docker compose restart stalwart
    ;;
  apply)
    cli apply --file plan.ndjson
    docker compose restart stalwart
    docker compose logs --tail 20 stalwart
    ;;
  user)
    name=${2:?usage: configure.sh user NAME}
    read -r -s -p "Password for $name@$DOMAIN: " pw; echo
    dom_id=$(cli query Domain --fields id,name --json | python3 -c \
      "import sys,json; print(next(r['id'] for r in map(json.loads,sys.stdin) if r.get('name')=='$DOMAIN'))")
    cli create Account/User \
      --field name="$name" \
      --field domainId="$dom_id" \
      --field "credentials={\"0\":{\"@type\":\"Password\",\"secret\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$pw")}}"
    ;;
  dns)
    dom_id=$(cli query Domain --fields id,name --json | python3 -c \
      "import sys,json; print(next(r['id'] for r in map(json.loads,sys.stdin) if r.get('name')=='$DOMAIN'))")
    cli get Domain "$dom_id" --fields dnsZoneFile
    ;;
  cli)
    shift; cli "$@"
    ;;
  *)
    sed -n '2,13p' "$0"; exit 1
    ;;
esac
