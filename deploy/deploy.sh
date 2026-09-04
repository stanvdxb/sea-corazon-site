#!/usr/bin/env bash
# Publish the site.  Usage: deploy/deploy.sh [ssh-target]   (default: corazon)
# Refuses to deploy a build that fails local checks, and reports a real pass/fail
# for every live check rather than only for assets.
set -uo pipefail
TARGET=${1:-corazon}
DOMAIN=corazon-tech.com
WEBROOT=/var/www/$DOMAIN
fails=0
note() { printf '   %-46s %s\n' "$1" "$2"; }
bad()  { fails=$((fails+1)); printf '   \033[31m%-46s %s\033[0m\n' "$1" "$2"; }
chk()  { [ "$2" = "$3" ] && note "$1" "$2" || bad "$1" "$2 (expected $3)"; }

echo ">> local integrity"
python3 .firecrawl/check-site.py | tail -1 | grep -q "no problems" \
  || { echo "check-site.py reports problems — refusing to deploy"; python3 .firecrawl/check-site.py; exit 1; }

# The CSP pins the inline <head> script by hash. If that script changes and the
# nginx snippet is not regenerated, every page silently loses its theme + reveal.
echo ">> CSP hash matches the inline script"
LOCAL_HASH=$(python3 -c "
import re,hashlib,base64,sys
s=open('index.html').read()
m=re.search(r'<script>(\(function\(\)\{var h=document.*?)</script>', s, re.S)
sys.exit('inline bootstrap script not found') if not m else None
print('sha256-'+base64.b64encode(hashlib.sha256(m.group(1).encode()).digest()).decode())")
grep -q "$LOCAL_HASH" deploy/nginx/security-headers.conf \
  && note "csp hash" "matches" \
  || { echo "   CSP hash in deploy/nginx/security-headers.conf is stale."; echo "   expected: $LOCAL_HASH"; echo "   regenerate it and re-run server-setup.sh (or scp the snippet)."; exit 1; }

echo ">> sync site (rsync elevates on the far side; the web root is root-owned)"
rsync -az --delete --human-readable --rsync-path="sudo rsync" \
  --exclude '.git' --exclude '.firecrawl' --exclude 'deploy' --exclude 'README.md' --exclude 'README.TXT' \
  --exclude '.claude' --exclude '.impeccable' --exclude '.playwright-mcp' \
  --exclude '.DS_Store' --exclude '__pycache__' --exclude '.gitignore' \
  ./ "$TARGET:$WEBROOT/" || { echo "rsync failed"; exit 1; }

echo ">> sync the form API and header snippet, then reload"
scp -q deploy/contact-api/contact_api.py "$TARGET:/tmp/contact_api.py"
scp -q deploy/nginx/security-headers.conf "$TARGET:/tmp/corazon-security-headers.conf"
scp -q deploy/nginx/cloudflare-realip.conf "$TARGET:/tmp/cloudflare-realip.conf"
ssh "$TARGET" "
  set -e
  sudo install -m 644 /tmp/contact_api.py /opt/contact-api/contact_api.py
  sudo install -m 644 /tmp/corazon-security-headers.conf /etc/nginx/snippets/corazon-security-headers.conf
  sudo install -m 644 /tmp/cloudflare-realip.conf /etc/nginx/snippets/cloudflare-realip.conf
  rm -f /tmp/contact_api.py /tmp/corazon-security-headers.conf /tmp/cloudflare-realip.conf
  sudo chown -R root:root $WEBROOT && sudo find $WEBROOT -type d -exec chmod 755 {} + && sudo find $WEBROOT -type f -exec chmod 644 {} +
  sudo nginx -t
  sudo systemctl reload nginx
  sudo systemctl restart contact-api 2>/dev/null || true
  sudo ufw status | grep -E '^(80|443)/tcp' || echo '  !! 80/443 not allowed by ufw'
" || { echo "remote step failed"; exit 1; }

echo ">> live verification (public internet)"
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$@" 2>/dev/null || echo ERR; }
chk "http apex -> redirect"  "$(code -I "http://$DOMAIN/")"        301
chk "https apex"             "$(code "https://$DOMAIN/")"          200
chk "https www -> redirect"  "$(code -I "https://www.$DOMAIN/")"   301
chk "404 page"               "$(code "https://$DOMAIN/no-such-page")" 404
for a in assets/css/style.css assets/js/main.js favicon.ico sitemap.xml robots.txt contact.html faq.html; do
  chk "$a" "$(code "https://$DOMAIN/$a")" 200
done
chk "POST /api/contact (empty)" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -X POST -H 'Content-Type: application/json' -d '{}' "https://$DOMAIN/api/contact" 2>/dev/null || echo ERR)" 422

echo ">> security headers (must be present on an HTML page AND on an asset)"
for path in "" "assets/css/style.css"; do
  H=$(curl -sSI --max-time 20 "https://$DOMAIN/$path" 2>/dev/null)
  for h in strict-transport-security content-security-policy x-content-type-options; do
    grep -qi "^$h" <<<"$H" && note "${path:-/} $h" "present" || bad "${path:-/} $h" "MISSING"
  done
done

echo ">> certificate"
echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate 2>/dev/null | sed 's/^/   /' || bad "certificate" "unreadable"

if [ "$fails" -eq 0 ]; then echo ">> deploy verified"; else echo ">> DEPLOY VERIFICATION FAILED ($fails checks)"; exit 1; fi
