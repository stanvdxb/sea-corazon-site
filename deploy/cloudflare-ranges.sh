#!/usr/bin/env bash
# Refresh the Cloudflare edge ranges used for real-IP recovery (and, optionally,
# the firewall). Cloudflare changes these rarely; re-run if they announce a change.
#   deploy/cloudflare-ranges.sh            regenerate the nginx snippet
#   deploy/cloudflare-ranges.sh --ufw      also print the ufw rules to lock the origin
set -euo pipefail
cd "$(dirname "$0")/.."
V4=$(curl -fsS --max-time 20 https://www.cloudflare.com/ips-v4)
V6=$(curl -fsS --max-time 20 https://www.cloudflare.com/ips-v6)
[ -n "$V4" ] && [ -n "$V6" ] || { echo "could not fetch Cloudflare ranges"; exit 1; }
{
  echo "# Real visitor IPs behind Cloudflare. Without this nginx sees Cloudflare's"
  echo "# addresses, so the per-IP rate limit on /api/contact would throttle every"
  echo "# visitor as one, and the form would log the proxy instead of the sender."
  echo "# Regenerate with: deploy/cloudflare-ranges.sh"
  echo "# Generated from https://www.cloudflare.com/ips-v4 and ips-v6"
  echo
  echo "$V4" | while read -r r; do [ -n "$r" ] && echo "set_real_ip_from $r;"; done
  echo
  echo "$V6" | while read -r r; do [ -n "$r" ] && echo "set_real_ip_from $r;"; done
  echo
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
} > deploy/nginx/cloudflare-realip.conf
echo "wrote deploy/nginx/cloudflare-realip.conf ($(grep -c set_real_ip_from deploy/nginx/cloudflare-realip.conf) ranges)"

if [ "${1:-}" = "--ufw" ]; then
  echo
  echo "# Lock the origin so only Cloudflare can reach 80/443. Run on the server as root."
  echo "# WARNING: after this, grey-clouding a web record takes the site offline."
  echo "ufw delete allow 80/tcp  2>/dev/null || true"
  echo "ufw delete allow 443/tcp 2>/dev/null || true"
  { echo "$V4"; echo "$V6"; } | while read -r r; do
    [ -n "$r" ] && echo "ufw allow proto tcp from $r to any port 80,443 comment 'Cloudflare'"
  done
fi
