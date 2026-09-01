# manageships-clone

A static visual clone of [manageships.com](https://manageships.com) (Sea Corazon Ship Management - FZCO), rebuilt from the live site's content and design tokens.

## Origin

The original is a WordPress site on the **Astra** theme (Russian-locale install, English content). This clone is a dependency-free static rebuild — plain HTML/CSS/JS, no WordPress, no build step.

## Design tokens (extracted from the original)

| Token | Value |
|---|---|
| Primary navy | `#164e72` |
| Accent gold | `#e1963a` |
| Steel blue | `#477da4` |
| Surface | `#F0F5FA` |
| Typography | Roboto Condensed (400/500/600/700) |

## Structure

```
index.html            — homepage (all sections of the original)
assets/css/style.css  — design system + layout (responsive, a11y)
assets/js/main.js     — mobile nav, testimonial slider, scroll-to-top, reveal
assets/img/           — 46 images mirrored from the original site
original.html         — raw saved HTML of the source page (reference)
```

## Run locally

```bash
python3 -m http.server 8080
# open http://localhost:8080
```

## What's included vs. original

- ✅ All homepage sections: hero, team/priorities split, callback form, gallery, about, 4 service cards, banner, priorities, sea transport, testimonials slider, contact form
- ✅ Real images (mirrored from wp-content/uploads)
- ✅ Mobile nav, sticky header, scroll-to-top
- ⚠️ Forms are static stubs (original posts to WP + reCAPTCHA)
- ⚠️ Sub-pages (services detail, contact) not cloned — links point to sections

> Note: content and images belong to Sea Corazon Ship Management - FZCO. This clone is for local study/development only.
