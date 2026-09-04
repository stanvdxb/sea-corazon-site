===============================================================================
 SEA CORAZON SHIP MANAGEMENT FZCO - WEBSITE
 Maintenance and operations guide
 Last updated: 2026-09-04
===============================================================================

WHAT THIS IS
-------------------------------------------------------------------------------
The company website, https://corazon-tech.com

It is a plain static site: 15 pages plus a "not found" page, one stylesheet,
and one small JavaScript file. No WordPress, no framework, no database, nothing to keep patched at the
application level. The only moving part is a small contact-form service.

Source code:  https://github.com/stanvdxb/sea-corazon-site
Server:       Hetzner VPS, 2.28.46.26, Ubuntu 24.04 LTS
DNS + CDN:    Cloudflare (proxied)
Email:        Microsoft 365


QUICK REFERENCE
-------------------------------------------------------------------------------
Website files on the server   /var/www/corazon-tech.com/
Deployment scripts            /opt/site-deploy/deploy/
nginx site config             /etc/nginx/sites-available/corazon-tech.com.conf
nginx snippets                /etc/nginx/snippets/
Contact form service          /opt/contact-api/contact_api.py
Contact form credentials      /etc/contact-api.env          (root only, 0600)
Cloudflare API token          /etc/letsencrypt/cloudflare.ini (root only, 0600)
TLS certificate               /etc/letsencrypt/live/corazon-tech.com/

Services (all start automatically on boot):
    nginx                 the web server
    contact-api           receives contact form submissions, emails them
    fail2ban              blocks SSH brute-force attempts
    unattended-upgrades   applies security updates automatically

Check them all at once:
    systemctl status nginx contact-api fail2ban unattended-upgrades


PUBLISHING A CHANGE TO THE WEBSITE
-------------------------------------------------------------------------------
Edit the files in the Git repository, then from a computer with SSH access to
the server:

    deploy/deploy.sh <user>@2.28.46.26

The script will refuse to publish if anything is broken, and after publishing it
checks the live site from the public internet: redirects, security headers, the
certificate, every asset, and the form endpoint. If any check fails it exits
with an error rather than reporting success.

To edit directly on the server instead (not recommended - changes are lost on
the next deployment and are not in version control):

    /var/www/corazon-tech.com/


ROUTINE MAINTENANCE
-------------------------------------------------------------------------------
Security updates apply themselves. If a kernel update needs a reboot, the server
reboots itself at 04:30 and the site returns within seconds.

Every few months, or after any change, run a health check as root:

    bash /opt/site-deploy/deploy/server-update.sh

It applies updates, renews the certificate if due, and reports the state of
every service, the firewall, disk and memory, and whether a reboot is pending.
It never reboots by itself.


THE TLS CERTIFICATE
-------------------------------------------------------------------------------
Let's Encrypt, covering corazon-tech.com and www.corazon-tech.com.
Renews automatically about 30 days before expiry, roughly every 60 days.

Renewal was tested end to end on 2026-09-04 and succeeded.

How it works: renewal proves domain ownership by creating a temporary DNS record
through the Cloudflare API. That requires the token in
/etc/letsencrypt/cloudflare.ini.

  >> IF THE CLOUDFLARE API TOKEN IS EVER CHANGED, ROLLED OR DELETED, RENEWAL
  >> STOPS WORKING - SILENTLY. Nothing will warn you. About 60 days later the
  >> site begins showing a certificate error to every visitor.

  After changing the token, run as root:
      cd /opt/site-deploy && bash deploy/set-cloudflare-token.sh

To check the certificate is healthy at any time, as root:

    certbot certificates          shows expiry
    certbot renew --dry-run       simulates the whole renewal

Do not judge this from a browser. Visitors see Cloudflare's own certificate, not
the one on the server, so the padlock can look fine while the server certificate
has expired. To check the server itself, from any computer:

    echo | openssl s_client -connect 2.28.46.26:443 \
        -servername corazon-tech.com 2>/dev/null | openssl x509 -noout -enddate

SUGGESTED: put a calendar reminder in late October, and every October and April
thereafter, to run "certbot renew --dry-run". It takes five seconds and turns a
silent failure into a known one while there is still a month to fix it.


THE CONTACT FORM
-------------------------------------------------------------------------------
Every page has an enquiry form. Submissions are emailed to ops@corazon-tech.com
through Microsoft Graph (the Microsoft 365 API), using an app registration in
Entra with the application permission Mail.Send.

It does not use SMTP: Hetzner blocks outbound port 25, and Microsoft is retiring
SMTP basic authentication during 2026.

To change the recipient address, or after the Entra client secret expires:

    cd /opt/site-deploy && bash deploy/set-credentials.sh

The script prompts for each value, sends a real test message, and tells you
whether it worked. Nothing is typed on the command line, so no credential ends
up in the shell history.

  >> ENTRA CLIENT SECRETS EXPIRE. Whoever created the app registration should
  >> note the expiry date. When it lapses the form stops sending, and visitors
  >> are shown the phone number and email address instead of a false success.

To check the service:
    systemctl status contact-api
    journalctl -u contact-api -n 50


OUTSTANDING ITEMS
-------------------------------------------------------------------------------
1. DKIM IS BROKEN (email, not the website)
   In Cloudflare DNS, the two records named
       selector1._domainkey
       selector2._domainkey
   are set to "Proxied" (orange cloud). They must be "DNS only" (grey cloud).
   While proxied they return Cloudflare's web addresses instead of Microsoft's,
   so outbound email from @corazon-tech.com cannot be DKIM-verified. This harms
   deliverability. Fix: click the orange cloud on each of those two rows.

2. THE CLOUDFLARE API TOKEN WAS EXPOSED
   It was shared in a screenshot during setup and should be replaced. See the
   certificate section above for what to do after replacing it.

3. CONFIRM CLOUDFLARE SSL/TLS MODE IS "FULL (STRICT)"
   Under SSL/TLS > Overview. "Flexible" would be insecure and would break the
   site with a redirect loop.


THINGS THAT WILL BREAK THE SITE
-------------------------------------------------------------------------------
These are not obvious, which is why they are written down.

* Turning off the orange cloud on corazon-tech.com or www in Cloudflare while
  Cloudflare's SSL/TLS mode is "Flexible". Check the mode before changing proxy
  settings.

* Changing the Cloudflare API token without updating the server (see above).

* Editing the small <script> block in the <head> of the HTML pages. The server
  permits that exact script by a security fingerprint. If it changes, the theme
  switcher and scroll animations stop working on every page. deploy.sh detects
  this and refuses to publish, but only if you deploy through the script.

* Removing "precedence ::ffff:0:0/96 100" from /etc/gai.conf. This makes the
  server prefer IPv4 for outgoing connections. The Cloudflare API token is
  restricted to the server's IPv4 address, so without this line certificate
  renewal fails. Original file backed up as /etc/gai.conf.bak.20260904


IF THE SITE IS DOWN
-------------------------------------------------------------------------------
1. Is it the server or Cloudflare?
       curl -I https://2.28.46.26 --insecure --resolve corazon-tech.com:443:2.28.46.26
   A "521" or "522" error page from Cloudflare means the server is not
   responding. Anything else means Cloudflare is serving something.

2. On the server, as root:
       systemctl status nginx          is the web server running
       nginx -t                        is the configuration valid
       systemctl restart nginx         restart it
       df -h                           is the disk full
       journalctl -xe -n 50            recent system errors

3. Certificate expired? See the certificate section above.

4. Nothing else worked: reboot. The site comes back on its own.
       reboot


ACCESS AND CREDENTIALS
-------------------------------------------------------------------------------
Server SSH        root@2.28.46.26 (the temporary deployment account used during
                  setup was deleted on 2026-09-04)
Cloudflare        managed by the IT contact who administers DNS
Microsoft 365     Entra app registration "contact form", client secret in
                  /etc/contact-api.env on the server
GitHub            https://github.com/stanvdxb/sea-corazon-site

No password or secret is stored in the Git repository. The two credential files
on the server are readable by root only.


TECHNICAL NOTES
-------------------------------------------------------------------------------
Full technical documentation, including the design system, colour tokens,
component list and the reasoning behind the Cloudflare configuration, is in
README.md in the repository.

Site content was reproduced from the previous website at manageships.com.
Photography is inherited from that site. The FAQ answers were written from the
company's own service descriptions and should be reviewed for accuracy.

===============================================================================
