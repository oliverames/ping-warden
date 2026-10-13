# Ping Warden website

The static product site at https://pingwarden.app. Cloudflare Workers serves only
`public/`. Gumroad continues to handle purchases, downloads, and license delivery.
The app's signed update feeds and release process remain independent of this site.

## Preview and deploy

From this directory:

```sh
npm ci
npm run build
npm run check
npm run dev
npx wrangler deploy --dry-run
npm run deploy
```

Use an existing Cloudflare login or load credentials from 1Password into the
process environment. Never save credentials in this directory. The configuration
binds the apex and www domains. The www host redirects to the apex.

`build.mjs` renders the complete root README, technical guide, Quick Start,
troubleshooting, security policy, and release notes into static HTML. It rewrites
guide links, generates heading anchors, structured data, and the sitemap. Edit
the source Markdown and `home.html`, then rebuild the committed pages. The build
is deterministic, and Website Verification checks that source and output agree.

The home page version and the release-notes sitemap date come from the newest
item in the root `appcast.xml`, so rebuild the site after each release. Gumroad
links carry a `referrer` parameter per surface (`pingwarden-hero`,
`pingwarden-reviews`, `pingwarden-nav`, `pingwarden-docs`, `pingwarden-guide`)
so Gumroad Analytics separates them.

There is no browser JavaScript, external font request, or analytics. The only
Worker code redirects HTTP and www to the canonical HTTPS apex, redirects the
retired `/dashboard.png` address, and passes requests to static assets. The
dashboard image comes from `docs/images/ping-warden-4-dashboard.png`. The build
copies it to `dashboard-v4.png`. When the screenshot changes, regenerate the
committed WebP variants from `public/`:

```sh
cwebp -q 82 -resize 2000 0 dashboard-v4.png -o dashboard-v4-2000.webp
cwebp -q 82 -resize 1000 0 dashboard-v4.png -o dashboard-v4-1000.webp
```

`favicon.ico`, `favicon-32x32.png`, and `apple-touch-icon.png` (180 px on a
white background) are derived from `app-icon.png`.
The app icon comes from the existing Gumroad landing page. The generated design
concept is a visual reference only and is not shipped as product imagery.

After edits, check mobile and desktop layouts, keyboard navigation, disclosure
controls, image loading, purchase and download links, and unknown-path 404s.
After deployment, check both custom domains and compare deployed files with
`public/`. The root `landing.html` is the retired custom Gumroad landing artifact.
Gumroad uses its standard page with `docs/gumroad-product-description.html` as
the product description. Do not republish the retired custom page.
