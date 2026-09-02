# Sea Corazon Ship Management — website

The website of **Sea Corazon Ship Management FZCO**, a Dubai ship management company.
Plain HTML, one stylesheet, one small script. No framework, no build step, nothing to install.

## Running it

```bash
python3 -m http.server 8765
# open http://127.0.0.1:8765/
```

Any static host serves it as-is. It is currently published from this repository by GitHub Pages at
<https://stanvdxb.github.io/sea-corazon-site/> — every push to `main` redeploys within a minute or two.
`sitemap.xml` and `robots.txt` assume the final home is `https://manageships.com/`; point that domain at Pages
(a `CNAME` file plus DNS) when ready, or change the host in both files if it moves elsewhere.

## What's here

```
index.html                                home
ship-management-company.html              About Us
services-ship-management.html             Ship management services
  technical-ship-management.html
  crew-management.html
  opex-management.html
  fleet-management-services.html
sea-transport-services.html               Sea transport services
  international-sea-transport.html
  sea-transportation-of-liquid-cargo.html
  transportation-of-bulk-cargo.html
faq.html · contact.html · privacy-policy.html · sitemap.html

assets/css/style.css        the whole design system (~880 lines)
assets/js/main.js           nav, accordion, tabs, carousel, scroll-to-top, form interception
assets/img/                 photography: WebP at 480/768/1200 px, PNG/JPEG fallback
assets/icons/               favicon set generated from the logo's heart mark
site.webmanifest · favicon.ico · sitemap.xml · robots.txt
```

`.firecrawl/` is git-ignored working material — the original site capture this was rebuilt from, extraction notes, verification screenshots, and `check-site.py`.

## Design

**Palette from the logo, nothing else.** Every colour is sampled from `assets/img/design-1-optimized.png`:

| token | value | role |
|---|---|---|
| `--navy` | `#002050` | headings, wordmark, top bar |
| `--navy-deep` | `#001438` | footer |
| `--blue` | `#1058A0` | the one action colour: every button, every link |
| `--blue-deep` | `#0B4680` | hover |
| `--blue-soft` | `#2A66AE` | gradients and tints only, never a text ground |

Every foreground/background pair used for text is ≥ 4.5 : 1 (white on `--blue` is 7.2 : 1, on `--navy` 15.9 : 1). The palette script that generated `:root` refuses to write if any pair fails.

**Type:** Roboto Condensed (300–700) throughout; Alumni Sans on one display band; Heebo on the footer's small links. Body 16 px, nothing in `<main>` below 15 px.

**Breakpoints:** 1024 px (nav collapses) and 767 px (single column). Every interactive element is at least 44 × 44 px at every width. On narrow screens the service-page sidebar follows the article instead of preceding it.

**Dark theme:** follows the system preference automatically; the header toggle overrides it and remembers the choice. Only the role tokens (`--bg`, `--surface`, `--heading`, `--link`, `--ink*`) are remapped — brand colours don't change — and every dark text pair is ≥ 4.5 : 1. The masthead swaps to the light lock-up of the logo.

**Motion:** `prefers-reduced-motion` removes decorative transitions (image zoom, fades) but keeps state changes — accordion, tabs and carousel still switch, they just don't animate.

**Components** (`style.css` sections 6–21): header, home hero, inner-page banner, statement/display/CTA bands, split image+copy, cards (`.card--accent` for the alternating blue variant), chip cards, feature grid with inline SVG icons, checklist, accordion, tabs, carousel (scroll-snap + dots; replaces Swiper), sidebar layout, forms, footer. Photographic sections take a colour wash modifier (`.wash--navy`, `.wash--radial`, `.wash--sea`, `.wash--fade`).

## Copy

Headings carry their own weight; there are no kicker/eyebrow labels above them. Marketing filler ("cutting-edge", "world of possibilities", "streamlined") was rewritten into plain statements of what the company does, **using only facts already stated on the site** — no fleet sizes, countries, certifications or clients were added. Testimonials are reproduced verbatim as quoted third parties.

The FAQ has seven questions answered from the site's own service descriptions. **They should be read and confirmed by Sea Corazon before launch** — they are accurate to the site's copy, not verified with the company.

## Forms

The three forms (callback card, footer enquiry, contact page) are intercepted by `main.js` and acknowledge in place. They post nowhere. Wire `data-clone-form` forms to a real endpoint before launch.

## Known and deliberate

- The address (Office 204, Aspect Tower, Business Bay, Dubai) appears in the footer of every page and on `contact.html`; the contact map is centred on Aspect Tower. Contact email is ops@corazon-tech.com.
- PNG/JPEG fallbacks under `assets/img/` are the original 48 MB; browsers that understand WebP (≈97 %) never request them. Delete the fallbacks to shrink the deploy if legacy support isn't needed.

## Server

Deployment lives in `deploy/` and targets a Hetzner VPS running Ubuntu 24.04 LTS.

| Script | Where | What it does |
|---|---|---|
| `deploy/server-setup.sh` | on the server, as root, once | Full OS upgrade, nginx, certbot, ufw, the form API, TLS in two stages |
| `deploy/deploy.sh [target]` | from a workstation | Integrity check, rsync of the site only, then live verification over the internet |
| `deploy/server-update.sh` | on the server, as root, periodically | Updates, certificate renewal, service/firewall/disk health, reboot check |

**Updates.** Setup brings the server fully current, then installs `unattended-upgrades` so security
patches apply on their own, with automatic reboot at 04:30 when a kernel or libc update needs one —
nginx and `contact-api` are enabled at boot, so the site returns by itself. `fail2ban` guards SSH.
Neither setup nor update ever reboots while you are watching; a pending reboot is reported instead.

**Firewall.** `ufw` allows SSH, 80 and 443 — added *before* the firewall is enabled, so enabling can
never lock out the session — and setup aborts if any of the three is missing afterwards. `deploy.sh`
re-checks 80/443 after every deploy. Hetzner's separate *cloud* firewall lives in their web console and
is outside these scripts: if one is attached, it must also allow 80 and 443.

**Forms.** `POST /api/contact` is handled by `deploy/contact-api/contact_api.py` (standard library only)
and delivers to `ops@corazon-tech.com` through **Microsoft Graph** — OAuth client credentials over HTTPS,
so it needs neither port 25 (blocked by Hetzner) nor SMTP basic auth (being retired by Microsoft during
2026). An SMTP transport remains available via `MAIL_TRANSPORT=smtp`.

Credentials live in `/etc/contact-api.env` on the server, root-only, never in git. Create it by running
`sudo bash deploy/set-credentials.sh` **on the server** — it prompts for each value, reads the secret with
echo off, writes the file 0600, then proves the credentials by fetching a token and sending one real test
message. Nothing is passed as an argument, so nothing reaches shell history or a process listing.

The Entra app registration needs the **application** permission `Mail.Send` with admin consent. Restrict
it to the single mailbox with an [application access policy](https://learn.microsoft.com/graph/auth-limit-mailbox-access) —
without one, `Mail.Send` grants the app access to *every* mailbox in the tenant:

```powershell
New-ApplicationAccessPolicy -AppId <client-id> `
  -PolicyScopeGroupId ops@corazon-tech.com -AccessRight RestrictAccess `
  -Description "Website contact form: this mailbox only"
```

## Checking it

```bash
python3 .firecrawl/check-site.py
```

Walks every page for dead links, missing assets, images not served as WebP, pages without exactly one `<h1>`, stray `<style>` blocks, images without `alt`, undefined classes, leftover placeholder or obsolete text, eyebrow elements, and marketing buzzwords in the site's own copy.
