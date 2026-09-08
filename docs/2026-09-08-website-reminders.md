# Website and transition reminders, September 8, 2026

Author: Oliver Ames

## Website

[pingwarden.app](https://pingwarden.app/) is the new product website. Its design
uses white space, system typography, a restrained blue purchase action, and the
existing dashboard image. Apple Core supplied the simplicity reference. The
generated concept is not shipped as product imagery.

The documentation hub renders the complete root README, technical guide, Quick
Start, troubleshooting guide, security policy, and release history. Markdown
remains the source of truth. The deterministic build rewrites guide links and
anchors, generates structured data and the sitemap, and omits decorative badges.
Website Verification checks for stale generated output in GitHub Actions.

The app's Help menu, status menu, and About window link to the site. GitHub's
homepage and issue-template troubleshooting link use the domain. Gumroad now uses
its standard product page with concise copy and website links. The former custom
`landing.html` is retained as a retired artifact.

## Weekly reminders

The schedule uses the original transition deadline and a separate persisted
presentation timestamp. It never extends entitlement. Older installations use
their original grant date when no presentation timestamp exists.

Checks occur on launch, app activation, status-menu dismissal, and the existing
periodic entitlement check while the app is active. Detected games, latency
sessions, setup windows, and ongoing verification defer presentation. Missed weeks
produce one reminder. Activation or expiry stops reminders. A stored license key
suppresses purchase reminders during verification problems. The UI shows days
remaining and offers purchase, key entry, and dismissal.

The app update is 4.1.2, build 41200. Users must install it to receive the new
reminder behavior and Help links. Existing binaries cannot change remotely.

## Verification

- All eight indexable pages have unique titles, descriptions, canonical URLs,
  social metadata, and structured JSON. The sitemap matches those URLs.
- Structured data describes actual product details. No reviews or ratings are
  fabricated. Google's software-app rich result requires a genuine rating or
  review, so that search appearance is not claimed. See [Google's app schema
  guidance](https://developers.google.com/search/docs/appearance/structured-data/software-app).
- Content is static HTML with no browser JavaScript, external fonts, or analytics.
  Navigation uses real links. Images reserve layout space. Skip links, visible
  focus, native disclosures, and reduced-motion support are present.
- Nine HTML pages, local links, anchors, structured JSON, eight sitemap URLs, and
  both Worker routing tests passed. Repeated builds produced identical bytes.
- Browser checks at 320, 390, and 1280 pixels found no horizontal overflow in
  the checked landing and technical-guide layouts. Both hero actions fit in the
  initial 320 × 700 viewport. Disclosure interaction and section navigation
  worked. The browser reported no warnings or errors. Normal viewport captures
  were used because long captures showed stitching artifacts.
- The site follows [Google's SEO starter guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide).
  These checks establish crawlable content and accurate metadata, not indexing or
  ranking results. No Search Console submission is claimed.
- Cloudflare Worker version `6d2ccb49-4f6e-4eba-a20f-2cc7707e5d06` serves both
  custom domains with active certificates. The www redirect preserves path and
  query. Unknown paths return the custom page with HTTP 404. All 14 published
  page and asset files matched local bytes, including robots.txt and the sitemap.
- Gumroad custom HTML is cleared and its description matches the source file.
  Buyer content is unchanged. File identities and metadata are unchanged except
  rotating download URLs. Price, currency, refunds, shipping, purchase limits,
  and publication state were preserved during the page change.
- All 140 Swift core tests passed, including eight reminder cases. Nine release
  tool tests passed. The complete unsigned 4.1.2 app build passed. The exact
  reminder view was rendered using fictional state in a separate preview app,
  without modifying the installed app's data.

## Publication status

The implementation is committed and pushed as `b19177b`. Website Verification
and Build Verification passed on GitHub. The website and standard Gumroad product
page are live. Existing notary and Gumroad credentials passed their read-only
preflight checks.

Oliver approved publishing version 4.1.2 on September 8, 2026, after automatic
approval review initially held the release for explicit authorization. The
release is proceeding through signing, notarization, GitHub, update feeds, and
Gumroad. Completion will be recorded after verifying those receiving services.
