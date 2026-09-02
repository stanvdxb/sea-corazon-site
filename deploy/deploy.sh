#!/usr/bin/env bash
# Publish the site to the VPS. Usage: deploy/deploy.sh user@host
# Copies only what the browser needs; never the capture, the git history, or this folder.
set -euo pipefail
TARGET=${1:?usage: deploy/deploy.sh user@host}
python3 .firecrawl/check-site.py | tail -1 | grep -q "no problems" || { echo "check-site reports problems — not deploying"; exit 1; }
rsync -az --delete \
  --exclude .git --exclude .firecrawl --exclude deploy --exclude README.md --exclude .claude --exclude .impeccable --exclude .playwright-mcp --exclude '.DS_Store' \
  ./ "$TARGET:/var/www/corazon-tech.com/"
ssh "$TARGET" 'nginx -t && systemctl reload nginx && curl -s -o /dev/null -w "live: HTTP %{http_code}\n" https://corazon-tech.com/'
