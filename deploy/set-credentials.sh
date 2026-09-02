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
read -rsp "Client secret VALUE    : " SECRET; echo
read -rp  "Send mail AS (mailbox) [ops@corazon-tech.com]: " SENDER; SENDER=${SENDER:-ops@corazon-tech.com}
read -rp  "Deliver mail TO        [ops@corazon-tech.com]: " TO;     TO=${TO:-ops@corazon-tech.com}

for pair in "TENANT:$TENANT" "CLIENT:$CLIENT" "SECRET:$SECRET"; do
  [ -n "${pair#*:}" ] || { echo "${pair%%:*} cannot be empty"; exit 1; }
done
# A common mistake: pasting the secret's ID instead of its Value. IDs are GUIDs.
if [[ "$SECRET" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo; echo "That looks like a GUID — you have probably copied the secret's *ID*."
  echo "Go back and copy the *Value* column instead (it is shown only once, right after creation)."; exit 1
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
