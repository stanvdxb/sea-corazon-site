#!/usr/bin/env bash
# Put the Cloudflare API token on the server, for certbot's DNS-01 challenge.
# Run ON THE SERVER, as root:   sudo bash set-cloudflare-token.sh
# The token is typed at a prompt with echo off — never an argument, so it reaches
# no shell history, process listing or log. Written root-only (0600).
set -euo pipefail
INI=/etc/letsencrypt/cloudflare.ini
DOMAIN=corazon-tech.com
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }

echo
echo "Cloudflare API token for certificate renewal on $DOMAIN."
echo "It needs exactly: Zone -> DNS -> Edit, scoped to $DOMAIN."
echo
read -rsp "API token: " TOKEN; echo
[ -n "$TOKEN" ] || { echo "empty token"; exit 1; }
# The legacy Global API Key is 37 hex chars and must not be used here.
if [[ "$TOKEN" =~ ^[0-9a-f]{37}$ ]]; then
  echo "That looks like the Global API Key, which grants full account access."
  echo "Create a scoped API token instead (My Profile > API Tokens > Create Token)."; exit 1
fi

echo "Verifying the token with Cloudflare..."
VERIFY=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify || true)
grep -q '"success":true' <<<"$VERIFY" || { echo "Cloudflare rejected the token:"; echo "$VERIFY" | head -c 400; echo; exit 1; }
echo "  token is valid and active"

ZONES=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" || true)
grep -q '"success":true' <<<"$ZONES" && grep -q "\"name\":\"$DOMAIN\"" <<<"$ZONES" \
  && echo "  token can see the $DOMAIN zone" \
  || { echo "  the token is valid but cannot see $DOMAIN — check Zone Resources includes this zone"; exit 1; }

umask 077
TMP=$(mktemp /etc/letsencrypt/cloudflare.ini.XXXXXX)
printf 'dns_cloudflare_api_token = %s\n' "$TOKEN" > "$TMP"
chown root:root "$TMP"; chmod 600 "$TMP"; mv "$TMP" "$INI"
unset TOKEN
echo "Wrote $INI ($(stat -c '%U:%G %a' "$INI"))"
echo
echo "Next: sudo bash deploy/server-setup.sh   (it will now use DNS-01)"
