#!/usr/bin/env bash
# One-time VPS setup for corazon-tech.com. Debian/Ubuntu, run as root, on the server.
# Idempotent: safe to re-run. Never enables the firewall before SSH is permitted.
set -euo pipefail

DOMAIN=corazon-tech.com
EMAIL=ops@corazon-tech.com
WEBROOT=/var/www/$DOMAIN
SSH_PORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}'); SSH_PORT=${SSH_PORT:-22}

say() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
[ -d deploy ] || { echo "run from the repo root (deploy/ not found)"; exit 1; }

# Non-interactive for the whole run: Ubuntu 24.04 ships needrestart, which otherwise
# opens a curses prompt mid-upgrade and hangs an unattended SSH session.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

say "OS updates: bringing the server fully up to date"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
apt-get -y -q autoremove --purge
apt-get -y -q autoclean
echo "   $(dpkg -l | grep -c '^ii') packages installed, $(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0) still upgradable"

say "packages this site needs"
apt-get install -y -q nginx certbot python3-certbot-nginx python3 rsync ufw curl \
                      unattended-upgrades apt-listchanges fail2ban ca-certificates

say "ongoing security updates (unattended-upgrades)"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
CONF
cat > /etc/apt/apt.conf.d/51corazon-unattended <<'CONF'
// Security updates apply themselves. A kernel or libc update needs a reboot;
// this box serves static files, nginx and contact-api both start on boot, so a
// 04:30 reboot costs a few seconds of downtime and keeps the kernel current.
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
unattended-upgrade --dry-run --debug 2>&1 | tail -3 | sed 's/^/   /' || true

say "SSH brute-force protection (fail2ban)"
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
fail2ban-client status sshd 2>/dev/null | sed 's/^/   /' || echo "   fail2ban starting"

say "directories"
install -d -o www-data -g www-data "$WEBROOT" /var/www/certbot
[ -f "$WEBROOT/index.html" ] || echo '<!doctype html><title>Sea Corazon</title><p>Deploying…' > "$WEBROOT/index.html"

# ---------------------------------------------------------------- firewall
# Rules are ALWAYS added before enabling, so an enable can never lock out SSH.
say "firewall (ufw): allow SSH/$SSH_PORT, 80, 443 — then enable"
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 80/tcp  comment 'HTTP (ACME + redirect)'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
ufw status verbose
for p in "$SSH_PORT" 80 443; do
  ufw status | grep -qE "^${p}/tcp .*ALLOW" || { echo "FATAL: ufw is not allowing $p/tcp"; exit 1; }
done
echo "   ufw verified: $SSH_PORT, 80, 443 all ALLOW"

say "contact-form API"
install -d /opt/contact-api
install -m 644 deploy/contact-api/contact_api.py /opt/contact-api/contact_api.py
install -m 644 deploy/contact-api/contact-api.service /etc/systemd/system/contact-api.service
if [ ! -f /etc/contact-api.env ]; then
  install -m 600 deploy/contact-api/contact-api.env.example /etc/contact-api.env
  echo "   !! /etc/contact-api.env holds placeholders — real SMTP settings needed before forms work"
fi
systemctl daemon-reload
systemctl enable contact-api >/dev/null 2>&1 || true
systemctl restart contact-api || echo "   !! contact-api not running yet (expected until SMTP is configured)"

# ------------------------------------------------------- nginx, stage 1
say "nginx stage 1: HTTP only, so the server answers and ACME can validate"
rm -f /etc/nginx/sites-enabled/default
install -m 644 deploy/nginx/bootstrap.conf /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
nginx -t
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx
curl -fsS -o /dev/null -w '   local HTTP check: %{http_code}\n' http://127.0.0.1/ || { echo "FATAL: nginx not serving on 80"; exit 1; }

# ------------------------------------------------------------ certificate
say "DNS preflight (a wrong record burns Let's Encrypt rate limits)"
MYIP=$(curl -fsS --max-time 10 https://api.ipify.org || echo unknown)
for host in "$DOMAIN" "www.$DOMAIN"; do
  GOT=$(getent hosts "$host" | awk '{print $1}' | head -1)
  echo "   $host -> ${GOT:-NXDOMAIN}   (this server: $MYIP)"
  [ -n "$GOT" ] || { echo "FATAL: $host does not resolve. Add the A record, then re-run."; exit 1; }
  [ "$GOT" = "$MYIP" ] || echo "   !! $host does not point here yet — certbot will fail if this is still true"
done

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  say "certificate already present — renewing only if due"
  certbot renew --quiet || true
else
  say "requesting the certificate (webroot, so nginx config is never rewritten)"
  certbot certonly --webroot -w /var/www/certbot \
    -d "$DOMAIN" -d "www.$DOMAIN" \
    --non-interactive --agree-tos -m "$EMAIL" --no-eff-email
fi
[ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] || { echo "FATAL: no certificate issued"; exit 1; }
[ -f /etc/letsencrypt/options-ssl-nginx.conf ] || curl -fsS -o /etc/letsencrypt/options-ssl-nginx.conf https://raw.githubusercontent.com/certbot/certbot/main/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf
[ -f /etc/letsencrypt/ssl-dhparams.pem ] || openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048

# ------------------------------------------------------- nginx, stage 2
say "nginx stage 2: full config with TLS, headers, caching and the form proxy"
install -m 644 deploy/nginx/$DOMAIN.conf /etc/nginx/sites-available/$DOMAIN.conf
nginx -t
systemctl reload nginx

say "renewal"
systemctl list-timers certbot.timer --no-pager 2>/dev/null | tail -2 || true
certbot renew --dry-run --quiet && echo "   renewal dry-run OK"

say "post-setup verification"
curl -fsS -o /dev/null -w '   http://%{host} -> %{http_code} (expect 301)\n'  "http://$DOMAIN/"  || true
curl -fsS -o /dev/null -w '   https://%{host} -> %{http_code}\n'              "https://$DOMAIN/" || true
ss -tlnp 2>/dev/null | grep -E ':(80|443|8787)\b' | sed 's/^/   listening: /' || true
ufw status | sed 's/^/   ufw: /'
systemctl is-active --quiet unattended-upgrades && echo "   unattended-upgrades: active" || echo "   !! unattended-upgrades not active"
systemctl is-active --quiet fail2ban && echo "   fail2ban: active" || echo "   !! fail2ban not active"

if [ -f /var/run/reboot-required ]; then
  say "A REBOOT IS PENDING (kernel or core library updated)"
  cat /var/run/reboot-required.pkgs 2>/dev/null | sed 's/^/   /' || true
  echo "   Nothing here reboots automatically mid-setup. Reboot when convenient:  sudo reboot"
  echo "   nginx and contact-api are enabled, so the site returns on its own."
else
  echo "   no reboot required"
fi
say "setup complete — https://$DOMAIN"
