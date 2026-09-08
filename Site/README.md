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

There is no browser JavaScript, external font request, or analytics. The only
Worker code redirects www to the canonical apex and passes requests to static
assets. The dashboard image comes from `docs/images/ping-warden-3-dashboard.png`.
The app icon comes from the existing Gumroad landing page. The generated design
concept is a visual reference only and is not shipped as product imagery.

After edits, check mobile and desktop layouts, keyboard navigation, disclosure
controls, image loading, purchase and download links, and unknown-path 404s.
After deployment, check both custom domains and compare deployed files with
`public/`. The root `landing.html` is the retired custom Gumroad landing artifact.
Gumroad uses its standard page with `docs/gumroad-product-description.html` as
the product description. Do not republish the retired custom page.
