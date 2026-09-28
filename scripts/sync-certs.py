#!/usr/bin/env python3
"""Export the mail.leoschlanger.com certificate from Traefik's acme.json.

Traefik owns ports 80/443 and already renews Let's Encrypt certificates, so
Stalwart reuses them for SMTP/IMAP instead of running its own ACME client.
Writes /opt/mail/certs/<host>/{cert.pem,key.pem} (owned by UID 2000, the
Stalwart user) and restarts Stalwart only when the certificate changed.

Cron (root): 17 3 * * * /opt/mail/scripts/sync-certs.py >> /opt/mail/logs/sync-certs.log 2>&1
"""
import base64
import datetime
import json
import os
import subprocess
import sys



def read_env(path="/opt/mail/.env"):
    env = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k] = v
    return env


ENV = read_env()
ACME_JSON = ENV["TRAEFIK_ACME_JSON"]
RESOLVER = ENV["TRAEFIK_CERT_RESOLVER"]
HOSTNAME = os.environ.get("MAIL_HOSTNAME", "mail.leoschlanger.com")
OUT_DIR = f"/opt/mail/certs/{HOSTNAME}"
STALWART_UID = 2000


def log(msg):
    print(f"{datetime.datetime.now().isoformat(timespec='seconds')} {msg}", flush=True)


def find_cert():
    with open(ACME_JSON) as f:
        data = json.load(f)
    for entry in (data.get(RESOLVER) or {}).get("Certificates") or []:
        domain = entry.get("domain", {})
        names = [domain.get("main")] + (domain.get("sans") or [])
        if HOSTNAME in names:
            return base64.b64decode(entry["certificate"]), base64.b64decode(entry["key"])
    return None


def write_if_changed(path, content, mode):
    try:
        with open(path, "rb") as f:
            if f.read() == content:
                return False
    except FileNotFoundError:
        pass
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(content)
    os.chmod(tmp, mode)
    os.chown(tmp, STALWART_UID, STALWART_UID)
    os.replace(tmp, path)
    return True


def main():
    found = find_cert()
    if not found:
        log(f"no certificate for {HOSTNAME} in {ACME_JSON} yet (DNS set? Traefik router loaded?)")
        return 1
    cert, key = found
    os.makedirs(OUT_DIR, exist_ok=True)
    os.chown(OUT_DIR, STALWART_UID, STALWART_UID)
    changed = write_if_changed(f"{OUT_DIR}/cert.pem", cert, 0o644)
    changed |= write_if_changed(f"{OUT_DIR}/key.pem", key, 0o600)
    if not changed:
        log("certificate unchanged")
        return 0
    log("certificate updated")
    if "--no-restart" not in sys.argv:
        running = subprocess.run(["docker", "ps", "-q", "-f", "name=^stalwart$"],
                                 capture_output=True, text=True).stdout.strip()
        if running:
            subprocess.run(["docker", "restart", "stalwart"], check=True)
            log("stalwart restarted to load the new certificate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
