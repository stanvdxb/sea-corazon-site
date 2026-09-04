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
echo "The token value is ~40 characters and starts with cfat_ on current"
echo "Cloudflare accounts. Paste it and press Enter; nothing will appear as you type."
read -rsp "API token: " RAW; echo

# Strip every kind of whitespace a paste can carry: spaces, tabs, CR, LF, and the
# non-breaking space that a copy out of a browser or document often includes.
TOKEN=$(printf '%s' "$RAW" | tr -d '[:space:]' | sed 's/\xc2\xa0//g')
unset RAW
[ -n "$TOKEN" ] || { echo "Nothing was entered."; exit 1; }

# Report the SHAPE of what arrived — never the value — so a wrong paste is obvious.
LEN=${#TOKEN}
echo "  received: $LEN characters"
if [[ "$TOKEN" =~ ^Bearer ]]; then
  echo
  echo "It starts with 'Bearer'. Paste only the token itself, without that word."; exit 1
fi
if [[ "$TOKEN" =~ ^[0-9a-f]{32}$ ]]; then
  echo
  echo "That is 32 hex characters — it looks like the ACCOUNT ID, not the API token."
  echo "The token is ~40 characters, usually starting with cfat_."; exit 1
fi
if [[ "$TOKEN" =~ ^[0-9a-f]{37}$ ]]; then
  echo
  echo "That looks like the Global API Key, which grants full account access."
  echo "Create a scoped API token instead (My Profile > API Tokens > Create Token)."; exit 1
fi
if ! [[ "$TOKEN" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo
  echo "The value contains characters a Cloudflare token never has"
  echo "(a token is only letters, digits, underscore and hyphen)."
  echo "This usually means the token NAME was pasted instead of the token VALUE"
  echo "(the value starts with cfat_ on current accounts),"
  echo "or the copy picked up surrounding text. The Value is shown only once,"
  echo "immediately after the token is created — if it was not saved, create a new token."; exit 1
fi
if [ "$LEN" -lt 30 ] || [ "$LEN" -gt 80 ]; then
  echo
  echo "A Cloudflare API token is about 40 characters; this is $LEN."
  echo "Check that the whole value was copied, and only the value."; exit 1
fi

echo "Verifying the token with Cloudflare..."
VERIFY=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify || true)
if ! grep -q '"success":true' <<<"$VERIFY"; then
  echo "Cloudflare rejected the token:"
  echo "$VERIFY" | head -c 400; echo
  case "$VERIFY" in
    *6111*|*"Invalid format for Authorization"*)
      echo
      echo "Code 6111 means the token string itself is malformed, not that the"
      echo "permissions are wrong. The value that reached Cloudflare was not a"
      echo "well-formed token — most often the token NAME, an Account ID, or a"
      echo "partial copy. Create a fresh token and copy the Value column." ;;
    *1000*|*"Invalid API Token"*)
      echo
      echo "The token is well-formed but not recognised. It may have been revoked,"
      echo "or belong to a different Cloudflare account." ;;
  esac
  exit 1
fi
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
