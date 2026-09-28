#!/usr/bin/env bash
# Install / re-install the mail stack on the VPS. Idempotent.
# Expects this repo cloned at /opt/mail and the TRAEFIK_* values filled in .env
# (the first run creates .env from .env.example and stops so you can edit it).
set -euo pipefail
cd /opt/mail
PUBLIC_IP=$(curl -4 -s https://ifconfig.me)

echo "==> .env"
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|^STALWART_RECOVERY_ADMIN=.*|STALWART_RECOVERY_ADMIN=admin:$(openssl rand -hex 16)|" .env
  sed -i "s|^BULWARK_SESSION_SECRET=.*|BULWARK_SESSION_SECRET=$(openssl rand -base64 32)|" .env
  chmod 600 .env
  echo "    generated .env with fresh secrets. Fill the TRAEFIK_* values, then run again."
  exit 0
fi
set -a; . ./.env; set +a
[ -d "$TRAEFIK_DYNAMIC_DIR" ] || { echo "ABORT: TRAEFIK_DYNAMIC_DIR '$TRAEFIK_DYNAMIC_DIR' not found" >&2; exit 1; }
[ -f "$TRAEFIK_ACME_JSON" ] || { echo "ABORT: TRAEFIK_ACME_JSON '$TRAEFIK_ACME_JSON' not found" >&2; exit 1; }
mkdir -p certs logs backups

echo "==> DNS preflight (public IP $PUBLIC_IP)"
for h in mail.leoschlanger.com webmail.leoschlanger.com; do
  ip=$(dig +short A "$h" @8.8.8.8 | tail -1)
  if [ "$ip" != "$PUBLIC_IP" ]; then
    echo "ABORT: $h resolves to '${ip:-nothing}', expected $PUBLIC_IP. Create the DNS records first (DNS.md)." >&2
    exit 1
  fi
done

echo "==> Traefik route"
sed "s/__CERT_RESOLVER__/$TRAEFIK_CERT_RESOLVER/" traefik/mail.yml > "$TRAEFIK_DYNAMIC_DIR/mail.yml"

echo "==> Waiting for Traefik to issue the mail.leoschlanger.com certificate"
for i in $(seq 1 30); do
  curl -s -o /dev/null --max-time 5 https://mail.leoschlanger.com/ || true
  if ./scripts/sync-certs.py --no-restart; then break; fi
  [ "$i" = 30 ] && { echo "ABORT: no certificate after 5 min, check the Traefik logs" >&2; exit 1; }
  sleep 10
done

echo "==> Firewall (UFW) for mail ports"
for p in 25 465 993; do ufw allow "$p/tcp" comment mail >/dev/null; done

echo "==> Start containers"
docker compose pull -q
docker compose up -d

echo "==> Cron jobs"
cat > /etc/cron.d/mail-stack <<'EOF'
# Managed by /opt/mail/scripts/install.sh
17 3 * * * root /opt/mail/scripts/sync-certs.py >> /opt/mail/logs/sync-certs.log 2>&1
45 4 * * * root /opt/mail/scripts/backup.sh >> /opt/mail/logs/backup.log 2>&1
EOF

echo
echo "Done. Next: /opt/mail/scripts/configure.sh (first install only)."
