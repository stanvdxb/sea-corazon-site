#!/usr/bin/env bash
# One-time VPS setup for corazon-tech.com. Ubuntu 24.04, run as root, from the repo root.
# Idempotent and non-destructive: a re-run never takes a working HTTPS site offline,
# and the firewall is never enabled before SSH is explicitly permitted.
set -euo pipefail

DOMAIN=corazon-tech.com
EMAIL=ops@corazon-tech.com
WEBROOT=/var/www/$DOMAIN
LIVE=/etc/letsencrypt/live/$DOMAIN
SNIPPET=/etc/nginx/snippets/corazon-security-headers.conf
AVAIL=/etc/nginx/sites-available/$DOMAIN.conf

say()  { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "run as root (sudo bash deploy/server-setup.sh)"
[ -d deploy ] || fail "run from the repo root — deploy/ not found"

# The SSH port must come from the RUNNING daemon. `sshd -T` needs root and can fail
# on a non-standard config; an empty result must never silently become 22 when the
# real port is different, so we fall back to the port of the current SSH session.
SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)
if [ -z "${SSH_PORT:-}" ] && [ -n "${SSH_CONNECTION:-}" ]; then SSH_PORT=$(awk '{print $4}' <<<"$SSH_CONNECTION"); fi
SSH_PORT=${SSH_PORT:-22}
case "$SSH_PORT" in ''|*[!0-9]*) fail "could not determine the SSH port (got '$SSH_PORT')";; esac

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1

say "OS updates"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
apt-get -y -q autoremove --purge
apt-get -y -q autoclean

say "packages"
apt-get install -y -q nginx certbot python3-certbot-nginx python3-certbot-dns-cloudflare python3 rsync ufw curl \
                      unattended-upgrades apt-listchanges fail2ban ca-certificates dnsutils
nginx -v 2>&1 | sed 's/^/   /'

say "ongoing security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
CONF
cat > /etc/apt/apt.conf.d/51corazon-unattended <<'CONF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
Unattended-Upgrade::SyslogEnable "true";
CONF
systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

say "fail2ban"
cat > /etc/fail2ban/jail.d/corazon.local <<'CONF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
[sshd]
enabled = true
CONF
systemctl enable --now fail2ban >/dev/null 2>&1 || true

say "firewall: allow SSH/$SSH_PORT, 80, 443 BEFORE enabling"
ufw allow "$SSH_PORT"/tcp comment 'SSH'   >/dev/null
ufw allow 80/tcp  comment 'HTTP (ACME + redirect)' >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
ufw --force enable >/dev/null
for p in "$SSH_PORT" 80 443; do
  ufw status | grep -qE "^${p}/tcp[[:space:]]+ALLOW" || fail "ufw is not allowing ${p}/tcp — refusing to continue"
done
ufw status | sed 's/^/   /'

say "web root"
install -d -o root -g root -m 755 "$WEBROOT"
install -d -o root -g root -m 755 /var/www/certbot
[ -e "$WEBROOT/index.html" ] || echo '<!doctype html><title>Sea Corazon</title><p>Deploying…' > "$WEBROOT/index.html"

say "contact-form API"
install -d /opt/contact-api
install -m 644 deploy/contact-api/contact_api.py /opt/contact-api/contact_api.py
install -m 644 deploy/contact-api/contact-api.service /etc/systemd/system/contact-api.service
# never overwrite real credentials on a re-run
if [ ! -f /etc/contact-api.env ]; then
  install -m 600 deploy/contact-api/contact-api.env.example /etc/contact-api.env
  echo "   /etc/contact-api.env created from the template — real SMTP settings still needed"
else
  echo "   /etc/contact-api.env already present — left untouched"
fi
systemctl daemon-reload
systemctl enable contact-api >/dev/null 2>&1 || true
systemctl restart contact-api 2>/dev/null || echo "   contact-api not started (expected until credentials are set)"

say "security-header snippet"
install -d /etc/nginx/snippets
install -m 644 deploy/nginx/security-headers.conf "$SNIPPET"
install -m 644 deploy/nginx/cloudflare-realip.conf /etc/nginx/snippets/cloudflare-realip.conf

# ---------------------------------------------------------------- certificate
# Stage 1 is installed ONLY when there is no certificate yet. Re-running a live
# server must never demote it to the HTTP-only bootstrap.
if [ -s "$LIVE/fullchain.pem" ] && [ -s "$LIVE/privkey.pem" ]; then
  say "certificate already present — leaving the live config in place"
  certbot renew --quiet || echo "   (renew check reported an issue; continuing)"
else
  CF_INI=/etc/letsencrypt/cloudflare.ini
  if [ -s "$CF_INI" ]; then
    # ---- DNS-01. Works with the Cloudflare proxy on, at issuance AND at every
    #      renewal, which HTTP-01 does not. The A record may legitimately point
    #      at Cloudflare rather than at this server, so no IP match is required.
    say "certificate via DNS-01 (Cloudflare token found)"
    chmod 600 "$CF_INI"; chown root:root "$CF_INI"
    for host in "$DOMAIN" "www.$DOMAIN"; do
      GOT=$(dig +short A "$host" @1.1.1.1 2>/dev/null | tail -1)
      printf '   %-24s -> %s\n' "$host" "${GOT:-NXDOMAIN}"
      [ -n "$GOT" ] || fail "$host does not resolve at all — add the record in Cloudflare, then re-run"
    done
    EXTRA=""
    [ -d "$LIVE" ] && [ ! -s "$LIVE/fullchain.pem" ] && EXTRA="--force-renewal"
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$CF_INI" \
      --dns-cloudflare-propagation-seconds 30 \
      -d "$DOMAIN" -d "www.$DOMAIN" \
      --non-interactive --agree-tos -m "$EMAIL" --no-eff-email $EXTRA \
      || fail "certbot DNS-01 failed — check the token scope (Zone:DNS:Edit on $DOMAIN) and /var/log/letsencrypt/letsencrypt.log"
  else
    # ---- HTTP-01 fallback, for a server that is NOT behind a proxy.
    say "no Cloudflare token at $CF_INI — falling back to HTTP-01"
    MYIP=$(curl -fsS --max-time 10 https://api.ipify.org || true)
    [ -n "$MYIP" ] || fail "could not determine this server's public IP"
    echo "   this server: $MYIP"
    BAD=0
    for host in "$DOMAIN" "www.$DOMAIN"; do
      GOT=$(dig +short A "$host" @1.1.1.1 2>/dev/null | tail -1)
      printf '   %-24s -> %s\n' "$host" "${GOT:-NXDOMAIN}"
      [ "$GOT" = "$MYIP" ] || BAD=1
    done
    [ "$BAD" -eq 0 ] || fail "DNS does not point at this server, and there is no Cloudflare token for DNS-01.
   Either run deploy/set-cloudflare-token.sh first (correct when the domain is proxied),
   or point the A records straight at $MYIP. certbot was NOT attempted."

    say "nginx stage 1: HTTP only, so ACME can validate"
    rm -f /etc/nginx/sites-enabled/default
    install -m 644 deploy/nginx/bootstrap.conf "$AVAIL"
    ln -sf "$AVAIL" /etc/nginx/sites-enabled/$DOMAIN.conf
    nginx -t || fail "bootstrap config invalid"
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx
    curl -fsS -o /dev/null http://127.0.0.1/ || fail "nginx is not serving on port 80"

    say "requesting the certificate"
    EXTRA=""
    [ -d "$LIVE" ] && [ ! -s "$LIVE/fullchain.pem" ] && EXTRA="--force-renewal"
    certbot certonly --webroot -w /var/www/certbot \
      -d "$DOMAIN" -d "www.$DOMAIN" \
      --non-interactive --agree-tos -m "$EMAIL" --no-eff-email $EXTRA \
      || fail "certbot could not issue the certificate — see /var/log/letsencrypt/letsencrypt.log"
  fi
fi
[ -s "$LIVE/fullchain.pem" ] || fail "no certificate at $LIVE"

# TLS helper files. Written atomically: an interrupted run must not leave a
# zero-byte file that [ -f ] considers present and nginx -t chokes on.
if [ ! -s /etc/letsencrypt/options-ssl-nginx.conf ]; then
  SRC=$(dpkg -L python3-certbot-nginx 2>/dev/null | grep -m1 'options-ssl-nginx.conf$' || true)
  [ -n "$SRC" ] || fail "options-ssl-nginx.conf not found in python3-certbot-nginx"
  install -m 644 "$SRC" /etc/letsencrypt/options-ssl-nginx.conf
fi
if [ ! -s /etc/letsencrypt/ssl-dhparams.pem ]; then
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem.tmp 2048
  mv /etc/letsencrypt/ssl-dhparams.pem.tmp /etc/letsencrypt/ssl-dhparams.pem
fi

say "renewal hook — without this, nginx keeps serving the OLD certificate after renewal"
install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh <<'HOOK'
#!/bin/sh
# certbot runs this after a successful renewal. nginx only reads certificates at
# start/reload, so without it the site serves the expired one until someone notices.
/usr/sbin/nginx -t && /bin/systemctl reload nginx
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh

# ------------------------------------------------------- nginx, stage 2
say "nginx stage 2: TLS, headers, caching, form proxy"
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx >/dev/null 2>&1 || true
[ -f "$AVAIL" ] && cp -a "$AVAIL" "$AVAIL.prev" || true
install -m 644 deploy/nginx/$DOMAIN.conf "$AVAIL"
ln -sf "$AVAIL" /etc/nginx/sites-enabled/$DOMAIN.conf
if ! nginx -t; then
  [ -f "$AVAIL.prev" ] && mv "$AVAIL.prev" "$AVAIL" && nginx -t && systemctl reload nginx || true
  fail "stage-2 config invalid — previous config restored"
fi
rm -f "$AVAIL.prev"
systemctl reload nginx

say "verification"
certbot renew --dry-run --quiet && echo "   renewal dry-run OK" || echo "   !! renewal dry-run FAILED"
[ -x /etc/letsencrypt/renewal-hooks/deploy/10-reload-nginx.sh ] && echo "   renewal reload hook installed"
printf '   http  -> %s (expect 301)\n' "$(curl -sS -o /dev/null -w '%{http_code}' -I "http://$DOMAIN/" || echo ERR)"
printf '   https -> %s (expect 200)\n' "$(curl -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN/" || echo ERR)"
for u in nginx contact-api unattended-upgrades fail2ban; do
  printf '   %-22s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || echo INACTIVE)"
done
ufw status | grep -E '^(80|443)/tcp' | sed 's/^/   ufw: /'

if [ -f /var/run/reboot-required ]; then
  say "REBOOT PENDING"; cat /var/run/reboot-required.pkgs 2>/dev/null | sed 's/^/   /' || true
  echo "   run 'sudo reboot' when convenient — nginx and contact-api restart on boot"
else
  echo "   no reboot required"
fi
say "setup complete — https://$DOMAIN"
