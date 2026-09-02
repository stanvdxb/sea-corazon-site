#!/usr/bin/env bash
# One-time VPS setup for corazon-tech.com (Debian/Ubuntu). Run as root on the server.
# Prerequisite: DNS A/AAAA for corazon-tech.com and www.corazon-tech.com point at this box.
set -euo pipefail
DOMAIN=corazon-tech.com

apt-get update -q
apt-get install -y -q nginx certbot python3-certbot-nginx python3 rsync ufw

# web root + certbot challenge root
install -d -o www-data -g www-data /var/www/$DOMAIN /var/www/certbot

# form API
install -d /opt/contact-api
install -m 644 deploy/contact-api/contact_api.py /opt/contact-api/contact_api.py
install -m 644 deploy/contact-api/contact-api.service /etc/systemd/system/contact-api.service
[ -f /etc/contact-api.env ] || { install -m 600 deploy/contact-api/contact-api.env.example /etc/contact-api.env; echo ">> edit /etc/contact-api.env with the real SMTP settings"; }
systemctl daemon-reload && systemctl enable --now contact-api

# nginx: start with the http-only server so certbot can validate, then let certbot add TLS
install -m 644 deploy/nginx/$DOMAIN.conf /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# certificate (both names), auto-renewal is installed by the certbot package
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --redirect -m ops@$DOMAIN
nginx -t && systemctl reload nginx

# firewall
ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable

echo ">> setup complete: https://$DOMAIN"
