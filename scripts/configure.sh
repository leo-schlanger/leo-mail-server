#!/usr/bin/env bash
# First-time Stalwart configuration, fully from the CLI (no web wizard).
#
#   configure.sh bootstrap   # 1. answer the setup wizard (Bootstrap object)
#   configure.sh apply       # 2. load stalwart/plan.ndjson (listener, TLS, CORS)
#   configure.sh user NAME [DOMAIN]  # 3. create NAME@DOMAIN (default leoschlanger.com)
#   configure.sh dns [DOMAIN]        # 4. print the DNS zone to publish
#   configure.sh cli ARGS    #    run any stalwart-cli command
#
# All steps talk to Stalwart on http://127.0.0.1:8480. Credentials:
#   - first install / recovery: STALWART_RECOVERY_ADMIN (user:password) in .env;
#   - afterwards (recovery admin removed): the permanent admin,
#     STALWART_ADMIN_USER (default admin@leoschlanger.com) and the password from
#     STALWART_ADMIN_PASSWORD or, if unset, asked for on the terminal.
# Fallback for step 1: open an SSH tunnel
#   ssh -L 8480:127.0.0.1:8480 personal-vps
# and use the wizard at http://localhost:8480/admin
set -euo pipefail
cd /opt/mail
DOMAIN=leoschlanger.com
HOST=mail.leoschlanger.com
CLI_IMAGE=stalwartlabs/cli:1.0.14   # pinned, tested on 0.16 (latest moved to 2.x on 2026-11-16)

# shellcheck disable=SC1091
set -a; . ./.env; set +a
if [ -n "${STALWART_RECOVERY_ADMIN:-}" ]; then
  ADMIN_USER=${STALWART_RECOVERY_ADMIN%%:*}
  ADMIN_PASS=${STALWART_RECOVERY_ADMIN#*:}
else
  ADMIN_USER=${STALWART_ADMIN_USER:-admin@leoschlanger.com}
  ADMIN_PASS=${STALWART_ADMIN_PASSWORD:-}
  if [ -z "$ADMIN_PASS" ]; then
    read -r -s -p "Stalwart password for $ADMIN_USER: " ADMIN_PASS </dev/tty; echo >&2
  fi
fi

cli() {
  docker run --rm -i --network host \
    -e XDG_CACHE_HOME=/tmp \
    -v "$PWD/stalwart":/work:ro -w /work \
    -e STALWART_URL=http://127.0.0.1:8480 \
    -e STALWART_USER="$ADMIN_USER" -e STALWART_PASSWORD="$ADMIN_PASS" \
    "$CLI_IMAGE" "$@"
}

domain_id() {  # id of a Domain by name
  cli query Domain --fields id,name --json | python3 -c \
    "import sys,json; print(next(r['id'] for r in map(json.loads,sys.stdin) if r.get('name')=='$1'))"
}

first_id() {  # id of the first object of a type (empty if none)
  cli query "$1" --fields id --json | python3 -c \
    "import sys,json; ids=[json.loads(l)['id'] for l in sys.stdin if l.strip()]; print(ids[0] if ids else '')"
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
    # POP3 (995) is not published by the compose file, so drop its listener:
    # otherwise autoconfig advertises a port nobody can reach.
    pop_id=$(cli query NetworkListener --fields id,name --json | python3 -c \
      "import sys,json; print(next((r['id'] for r in map(json.loads,sys.stdin) if r.get('name')=='pop3s'),''))")
    [ -z "$pop_id" ] || cli delete NetworkListener "$pop_id"
    # Certificate has no natural key, so it is created once instead of upserted.
    cert_id=$(first_id Certificate)
    if [ -z "$cert_id" ]; then
      cli create Certificate \
        --field "certificate={\"@type\":\"File\",\"filePath\":\"/certs/$HOST/cert.pem\"}" \
        --field "privateKey={\"@type\":\"File\",\"filePath\":\"/certs/$HOST/key.pem\"}"
      cert_id=$(first_id Certificate)
    fi
    cli update SystemSettings --field defaultHostname=$HOST --field defaultCertificateId="$cert_id"
    docker compose restart stalwart
    docker compose logs --tail 20 stalwart
    ;;
  user)
    name=${2:?usage: configure.sh user NAME [DOMAIN]}
    domain=${3:-$DOMAIN}
    read -r -s -p "Password for $name@$domain: " pw; echo
    dom_id=$(domain_id "$domain")
    cli create Account/User \
      --field name="$name" \
      --field domainId="$dom_id" \
      --field "credentials={\"0\":{\"@type\":\"Password\",\"secret\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$pw")}}"
    ;;
  dns)
    cli get Domain "$(domain_id "${2:-$DOMAIN}")" --fields dnsZoneFile
    ;;
  cli)
    shift; cli "$@"
    ;;
  *)
    sed -n '2,17p' "$0"; exit 1
    ;;
esac
