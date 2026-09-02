#!/usr/bin/env bash
# Publish the site. Usage: deploy/deploy.sh [ssh-target]   (default: corazon)
# Verifies the build locally, syncs, then checks the LIVE site from outside.
set -euo pipefail
TARGET=${1:-corazon}
DOMAIN=corazon-tech.com
WEBROOT=/var/www/$DOMAIN

echo ">> integrity check"
python3 .firecrawl/check-site.py | tail -1 | grep -q "no problems" \
  || { echo "check-site.py reports problems — refusing to deploy"; python3 .firecrawl/check-site.py; exit 1; }

echo ">> sync (site only: no git history, no capture, no deploy scripts)"
rsync -az --delete --human-readable \
  --exclude '.git' --exclude '.firecrawl' --exclude 'deploy' --exclude 'README.md' \
  --exclude '.claude' --exclude '.impeccable' --exclude '.playwright-mcp' \
  --exclude '.DS_Store' --exclude '__pycache__' --exclude '.gitignore' \
  ./ "$TARGET:$WEBROOT/"
ssh "$TARGET" "sudo chown -R www-data:www-data $WEBROOT && sudo nginx -t && sudo systemctl reload nginx"

echo ">> firewall still open after deploy"
ssh "$TARGET" 'sudo ufw status | grep -E "^(80|443)/tcp" || echo "  !! 80/443 NOT allowed by ufw"'

echo ">> live verification (from this machine, over the public internet)"
fail=0
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$@"; }
printf '   http  apex   -> %s (expect 301)\n' "$(code -I "http://$DOMAIN/")"
printf '   https apex   -> %s (expect 200)\n' "$(code "https://$DOMAIN/")"
printf '   https www    -> %s (expect 301)\n' "$(code -I "https://www.$DOMAIN/")"
printf '   404 page     -> %s (expect 404)\n' "$(code "https://$DOMAIN/no-such-page")"
for a in assets/css/style.css assets/js/main.js favicon.ico sitemap.xml robots.txt contact.html; do
  c=$(code "https://$DOMAIN/$a"); printf '   %-22s -> %s\n' "$a" "$c"; [ "$c" = 200 ] || fail=1
done
echo "   security headers:"
curl -sSI --max-time 15 "https://$DOMAIN/" | grep -iE 'strict-transport|content-security|x-content-type|x-frame|referrer-policy' | sed 's/^/     /'
echo "   certificate:"
echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates | sed 's/^/     /'
echo "   form API:"
printf '     POST /api/contact (empty) -> %s (expect 422)\n' \
  "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'Content-Type: application/json' -d '{}' "https://$DOMAIN/api/contact")"
[ "$fail" = 0 ] && echo ">> deploy verified" || { echo ">> DEPLOY VERIFICATION FAILED"; exit 1; }
