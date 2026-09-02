#!/usr/bin/env bash
# Routine maintenance for the corazon-tech.com server. Run as root, any time.
#   ssh corazon 'sudo bash -s' < deploy/server-update.sh
# Applies updates, confirms the site's services and firewall are healthy, and
# reports whether a reboot is pending. Never reboots on its own.
set -euo pipefail
DOMAIN=corazon-tech.com
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
say() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

say "before"
echo "   kernel: $(uname -r)   uptime:$(uptime -p | sed 's/up//')"
echo "   upgradable: $(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0)"

say "updating"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
apt-get -y -q autoremove --purge
apt-get -y -q autoclean

say "certificate"
certbot renew --quiet && echo "   renew check done"
if [ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -subject -enddate | sed 's/^/   /'
else
  echo "   !! no certificate at /etc/letsencrypt/live/$DOMAIN/"
fi

say "services"
for u in nginx contact-api unattended-upgrades fail2ban; do
  printf '   %-22s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || echo INACTIVE)"
done
nginx -t 2>&1 | sed 's/^/   /'

say "firewall"
ufw status | sed 's/^/   /'
for p in 80 443; do ufw status | grep -qE "^${p}/tcp .*ALLOW" || echo "   !! $p/tcp NOT allowed"; done

say "site responds"
curl -fsS -o /dev/null -w '   https://'"$DOMAIN"'/ -> %{http_code} in %{time_total}s\n' "https://$DOMAIN/" || echo "   !! site not responding"

say "disk and memory"
df -h / | tail -1 | sed 's/^/   /'
free -h | sed -n 2p | sed 's/^/   /'

if [ -f /var/run/reboot-required ]; then
  say "REBOOT PENDING"; cat /var/run/reboot-required.pkgs 2>/dev/null | sed 's/^/   /' || true
  echo "   run: sudo reboot   (nginx and contact-api come back on their own)"
else
  say "no reboot required"
fi
