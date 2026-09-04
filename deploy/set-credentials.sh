#!/usr/bin/env bash
# Put the Microsoft Graph credentials on the server.  Run ON THE SERVER, as root:
#
#     sudo bash set-credentials.sh
#
# Values are typed at the prompt, never passed as arguments, so nothing lands in
# shell history, process listings, or any log. The secret is read with echo off
# and is never printed back. The file it writes is root-only (0600).
set -euo pipefail
ENVFILE=/etc/contact-api.env
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }

echo
echo "Microsoft Graph credentials for the corazon-tech.com contact form."
echo "From Entra admin centre > App registrations > your app > Overview."
echo

read -rp "Directory (tenant) ID : " TENANT
read -rp "Application (client) ID: " CLIENT
echo "(the secret will not appear as you type — paste it ONCE, then press Enter)"
read -rsp "Client secret VALUE    : " RAWSECRET; echo
read -rp  "Send mail AS (mailbox) [ops@corazon-tech.com]: " SENDER; SENDER=${SENDER:-ops@corazon-tech.com}
read -rp  "Deliver mail TO        [ops@corazon-tech.com]: " TO;     TO=${TO:-ops@corazon-tech.com}

# Strip whitespace a paste can carry, then sanity-check the SHAPE — never the value.
TENANT=$(printf '%s' "$TENANT" | tr -d '[:space:]')
CLIENT=$(printf '%s' "$CLIENT" | tr -d '[:space:]')
SECRET=$(printf '%s' "$RAWSECRET" | tr -d '[:space:]'); unset RAWSECRET

for pair in "Tenant ID:$TENANT" "Client ID:$CLIENT" "Client secret:$SECRET"; do
  [ -n "${pair#*:}" ] || { echo "${pair%%:*} cannot be empty"; exit 1; }
done

GUID='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
[[ "$TENANT" =~ $GUID ]] || { echo "Tenant ID should be a GUID; got ${#TENANT} characters."; exit 1; }
[[ "$CLIENT" =~ $GUID ]] || { echo "Client ID should be a GUID; got ${#CLIENT} characters."; exit 1; }

echo "  secret received: ${#SECRET} characters"
if [[ "$SECRET" =~ $GUID ]]; then
  echo
  echo "That is a GUID — it is the client secret's ID, not its Value."
  echo "In Entra: Certificates & secrets > Client secrets > the VALUE column."; exit 1
fi
# An Entra client secret value is ~31-44 characters. Anything far outside that is
# a paste that swallowed neighbouring text (the description, expiry, or the ID).
if [ "${#SECRET}" -gt 60 ]; then
  echo
  echo "That is ${#SECRET} characters. An Entra client secret Value is about 40."
  if [ $(( ${#SECRET} % 40 )) -lt 6 ] || [ $(( ${#SECRET} % 44 )) -lt 6 ]; then
    echo
    echo "That length looks like the value pasted more than once. Nothing appears"
    echo "on screen while you type — that is deliberate, not a failed paste."
    echo "Paste once, then press Enter even though the line still looks empty."
  else
    echo "The copy has picked up extra text from the portal — usually the secret's"
    echo "Description, Expires date or Secret ID from the same table row."
    echo "Select only the Value cell and copy just that."
  fi
  exit 1
fi
if [ "${#SECRET}" -lt 20 ]; then
  echo
  echo "That is only ${#SECRET} characters — an Entra client secret Value is about 40."
  echo "It looks truncated; copy the whole Value."; exit 1
fi

umask 077
TMP=$(mktemp /etc/contact-api.env.XXXXXX)
cat > "$TMP" <<EOF
MAIL_TRANSPORT=graph
GRAPH_TENANT_ID=$TENANT
GRAPH_CLIENT_ID=$CLIENT
GRAPH_CLIENT_SECRET=$SECRET
GRAPH_SENDER=$SENDER
MAIL_TO=$TO
ALLOWED_ORIGIN=https://corazon-tech.com
EOF
chown root:root "$TMP"; chmod 600 "$TMP"; mv "$TMP" "$ENVFILE"
unset SECRET
echo; echo "Wrote $ENVFILE  ($(stat -c '%U:%G %a' "$ENVFILE"))"

echo
echo "Testing — this asks Entra for a token and sends one real message to $TO."
set +e
systemctl stop contact-api 2>/dev/null
env -i $(grep -v '^#' "$ENVFILE" | xargs) /usr/bin/python3 /opt/contact-api/contact_api.py --selftest
RC=$?
set -e
if [ $RC -eq 0 ]; then
  systemctl restart contact-api
  systemctl is-active --quiet contact-api && echo "contact-api is running. Check $TO for the test message."
else
  echo
  echo "The credentials did not work. Nothing else was changed; fix and re-run."
  echo "Common causes:"
  echo "  - Mail.Send was added as a Delegated permission; it must be APPLICATION."
  echo "  - Admin consent has not been granted (needs the Grant admin consent button)."
  echo "  - GRAPH_SENDER is not a real licensed mailbox in this tenant."
  exit 1
fi
