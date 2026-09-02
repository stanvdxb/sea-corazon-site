# manageships-clone

A dependency-free static clone of [manageships.com](https://manageships.com) — the site of
**Sea Corazon Ship Management FZCO**, a Dubai-based ship management company.

Captured with the Firecrawl CLI and rebuilt by hand as plain HTML, one stylesheet and one small
JavaScript file. No WordPress, no build step, no framework, no npm install.

## Running it

Any static server will do:

```bash
python3 -m http.server 8765
# then open http://127.0.0.1:8765/index.html
```

Opening `index.html` straight off the filesystem also works.

## What the original is

The source site is **WordPress + Astra + Elementor**, with ElementsKit, Metform, Popup Maker and
Header-Footer-Elementor on top. A live page pulls in 50+ stylesheets plus jQuery, React,
Google reCAPTCHA and a Cloudflare beacon.

None of that is reproduced. A byte-faithful mirror of that stack would be almost impossible to work
on, so the clone keeps the **content and the design** and throws away the delivery mechanism.

## Layout

```
index.html                              home
ship-management-company.html            About Us
services-ship-management.html           Ship management services (hub)
  technical-ship-management.html
  crew-management.html
  opex-management.html
  fleet-management-services.html
  auxiliary-ship-services.html          stub — see "Source defects" below
sea-transport-services.html             Sea transport services (hub)
  international-sea-transport.html
  sea-transportation-of-liquid-cargo.html
  transportation-of-bulk-cargo.html
faq.html
contact.html
privacy-policy.html
info.html / careers.html / sitemap.html stubs for links the source leaves dangling

assets/css/style.css                    the entire design system, ~780 lines
assets/js/main.js                       nav, accordions, scroll-to-top, form interception
assets/img/                             50 mirrored images
.firecrawl/                             scraped source material (git-ignored, not part of the site)
```

`.firecrawl/` holds the raw capture — original HTML, markdown, full-page screenshots, the Elementor
per-post stylesheets and the extracted content models. It is the evidence the clone was built from,
not part of the deliverable.

## Design tokens

Extracted from the live Elementor kit (`post-1222`) and the per-post stylesheets, not eyeballed.

| Token | Value | Used for |
|---|---|---|
| `--navy` | `#164E72` | brand, headings, links, top bar |
| `--navy-deep` | `#0A1D29` | footer |
| `--gold` | `#E1963A` | every call to action |
| `--blue-mid` | `#477DA4` | hover state |
| `--blue-light` | `#779CBB` | section eyebrows |
| `--ink` | `#334155` | body copy |
| `--surface-soft` | `#F0F5FA` | tinted sections |

Type is **Roboto Condensed** throughout (300/400/500/600/700), with **Alumni Sans** on the one
"Supply Chain Technology" band and **Heebo** on the footer's bottom-bar links — matching the source,
which loads Roboto, Roboto Slab and IBM Plex Sans but never applies them to anything visible.

Breakpoints are the source's own: **1024px** (tablet, nav collapses to a hamburger) and **767px** (mobile).

## Components

`assets/css/style.css` is the whole design system. Everything on the site is composed from these:

| Component | Class | Notes |
|---|---|---|
| Header | `.topbar` + `.masthead` + `.nav` | not sticky (the source isn't either); hamburger below 1024px |
| Home hero | `.hero` + `.photo-section` | copy in the left half over a full-bleed photo |
| Inner banner | `.page-banner` + `.breadcrumb` | **only** on About, Services, Sea transport, FAQ and Contact |
| Service-page hero | `.cta-band` | the 7 detail pages open with this, not a banner |
| Statement band | `.band`, `.band--display` | `--display` is the one Alumni Sans band |
| Split | `.split`, `.split--flip-mobile` | image collage + copy; flips to copy-first on mobile |
| Cards | `.card`, `.card--accent` | industry grids alternate blue/white 1-3-5 / 2-4-6 |
| Chip cards | `.chip-card` | gold badge over the image |
| Feature grid | `.feature` | inline SVG icons, never emoji |
| Accordion | `.accordion` | single-open, first item expanded |
| Tabs | `.tabs` | About page's "Vision & Strategy"; arrow-key navigable |
| Carousel | `.carousel` | testimonials; scroll-snap + dots, replaces Swiper |
| Forms | `.field`, `.form-row` | intercepted, no backend |
| Footer | `.footer-cta` + `.site-footer` | 4-column grid + bottom bar |

The colour washes over photographic sections are separate modifiers — `.wash--navy`, `.wash--grey`,
`.wash--radial`, `.wash--sea`, `.wash--fade` — matching the overlays the source's Elementor CSS applies.

## Checking it

```bash
python3 .firecrawl/check-site.py
```

Walks every page and reports dead local links, missing assets, pages without exactly one `<h1>`,
stray `<style>` blocks, images without `alt`, and any class used in markup that the stylesheet
never defines. It currently reports no problems across all 18 pages.

## Source defects reproduced or worked around

These are faults in the live site, recorded rather than silently fixed — the clone's job is fidelity.

- **`auxiliary-ship-services` returns HTTP 502.** It is linked from the footer of all 14 pages.
  The clone keeps the link and ships a stub page that says the page is unavailable.
- **The FAQ answers are Lorem ipsum.** So is the "Help Center" copy. Reproduced verbatim.
- **The "Info" nav item** points at `/category/uncategorized/`, an empty WordPress category archive.
  Cloned as `info.html` with the same empty state.
- **"Careers"** links to `#` in the source. Cloned as a stub.
- **Two phone numbers exist.** A hidden mobile-only footer variant uses `+97145727910`;
  everywhere else uses `+97145723303`. The clone standardises on the latter.
- **The top-bar email** is linked to the homepage rather than a `mailto:` in the source.
  The clone uses `mailto:` in both places.
- **The copyright still reads "© 2022"** although the site was last modified in 2026. Left as-is.
- **The install is Russian-locale** (`lang="ru-RU"`, Russian skip-link and menu labels) with English
  body copy. The clone is `lang="en"` with English chrome.
- **Casing is done in CSS, not in the text.** e.g. the hero source text is
  "Connect Your Business To A World Of Possibilities", uppercased by `text-transform`. Preserved.

## Deliberately not done

This is a clone, so it stops at fidelity. The following are known and deferred:

- **Images are unoptimised.** 50 MB of PNGs, several 1–2 MB each, for photographs that should be
  WebP or AVIF. This is inherited from the source and is the single biggest performance problem.
- No `srcset`/`sizes`, so every viewport downloads the desktop asset.
- Accessibility is at source parity, not at AA. Focus rings and skip links are kept and labels are
  present, but contrast, heading order and touch targets have not been audited.
- The source's form placeholders carry trailing spaces (`"Name "`, `"Message "`); the clone trims them.
- The source's "Message" field is a single-line `<input type="text">`; the clone uses a one-row
  `<textarea>`, which renders identically but grows when typed into.
- Popup Maker modals (the header "Contact Us" popup, the footer map popup) are not reproduced —
  those links go to `contact.html` instead.
- Forms are inert. The originals post to WordPress via Metform + reCAPTCHA; here submissions are
  intercepted and acknowledged in place rather than failing against a dead endpoint.

## Provenance

Captured 2026-09-02 with `firecrawl-cli` 1.23.3. Three pages (`faq`, `contact`, `privacy-policy`)
tripped the origin's shared-hosting resource limit (HTTP 508) under Firecrawl's renderer and were
fetched over plain HTTP instead; their screenshots came from Playwright.
