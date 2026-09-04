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

# A token created under "Account API tokens" is NOT verifiable at /user/tokens/verify —
# that endpoint only knows user-owned tokens and answers 1000 "Invalid API Token" for an
# account-owned one, which looks identical to a genuinely bad token. Try the checks that
# actually matter, in order, and accept the token if any of them proves it works.
OK=0; DETAIL=""

# 1. user-owned token
V=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
      https://api.cloudflare.com/client/v4/user/tokens/verify 2>/dev/null || true)
grep -q '"success":true' <<<"$V" && { OK=1; DETAIL="user-owned token, active"; }

# 2. account-owned token, if an account id is known or supplied
if [ "$OK" -eq 0 ]; then
  ACC="${CF_ACCOUNT_ID:-}"
  if [ -z "$ACC" ]; then
    read -rp "Cloudflare Account ID (blank to skip): " ACC
    ACC=$(printf '%s' "$ACC" | tr -d '[:space:]')
  fi
  if [ -n "$ACC" ]; then
    V=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
          "https://api.cloudflare.com/client/v4/accounts/$ACC/tokens/verify" 2>/dev/null || true)
    grep -q '"success":true' <<<"$V" && { OK=1; DETAIL="account-owned token, active"; }
  fi
fi

# 3. the capability we actually need: can it see the zone?
Z=$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
      "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" 2>/dev/null || true)
if grep -q '"success":true' <<<"$Z" && grep -q "\"name\":\"$DOMAIN\"" <<<"$Z"; then
  OK=1; DETAIL="${DETAIL:+$DETAIL; }can read the $DOMAIN zone"
fi

if [ "$OK" -eq 0 ]; then
  echo "Cloudflare did not accept the token."
  echo "  verify endpoint said: $(head -c 200 <<<"$V")"
  echo "  zone lookup said:     $(head -c 200 <<<"$Z")"
  echo
  echo "If this token was created under 'Account API tokens', supply the Account ID"
  echo "when prompted (or set CF_ACCOUNT_ID before running) so the right endpoint is used."
  echo "Otherwise the token may have been rolled, revoked, or scoped to another zone."
  echo
  echo "Note: this token is restricted to client IP 2.28.46.26, so it can only be"
  echo "verified from the server itself — running these checks elsewhere will fail."
  exit 1
fi
echo "  accepted: $DETAIL"

umask 077
# certbot may not be installed yet, so its config directory may not exist.
install -d -o root -g root -m 755 /etc/letsencrypt
TMP=$(mktemp /etc/letsencrypt/cloudflare.ini.XXXXXX)
printf 'dns_cloudflare_api_token = %s\n' "$TOKEN" > "$TMP"
chown root:root "$TMP"; chmod 600 "$TMP"; mv "$TMP" "$INI"
unset TOKEN
echo "Wrote $INI ($(stat -c '%U:%G %a' "$INI"))"
echo
echo "Next: sudo bash deploy/server-setup.sh   (it will now use DNS-01)"
