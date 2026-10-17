import { readFile, writeFile, mkdir, copyFile, readdir } from 'node:fs/promises';
import { dirname, resolve, relative, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import MarkdownIt from 'markdown-it';

const site = dirname(fileURLToPath(import.meta.url));
const root = resolve(site, '..');
const output = resolve(site, 'public');
const origin = 'https://pingwarden.app';
const gumroadProduct = 'https://amesconsulting.gumroad.com/l/pingwarden';
const githubRepo = 'https://github.com/oliverames/ping-warden';
const publisher = { '@type': 'Organization', name: 'Ames Consulting LLC', url: 'https://ames.consulting' };
// `updated` is maintained by hand and is the source of truth for each page's
// JSON-LD dateModified and sitemap lastmod. Deriving it from commit dates would
// change under squash merges and break the CI check that committed pages match
// the build. Bump it when a page's content changes.
const pages = [
  { source: 'README.md', slug: 'overview', updated: '2026-10-14', title: 'Features, Pricing, and Privacy', description: 'Explore Ping Warden features, the $15 Ping Protection license, the existing-user transition, privacy, system requirements, and source builds.' },
  { source: 'PingWarden/QUICKSTART.md', slug: 'setup', updated: '2026-10-17', title: 'Setup for Mac: Install, Approve, Verify', description: 'Set up Ping Warden on your Mac: install the app, enter your license key, approve the background helper in Login Items, and confirm Ping Protection is on.' },
  { source: 'PingWarden/README.md', slug: 'technical', updated: '2026-09-28', title: 'Technical Documentation', description: 'How Ping Warden works: AWDL events, the privileged helper, XPC, latency measurement, automation, security, diagnostics, and signed updates.' },
  { source: 'PingWarden/TROUBLESHOOTING.md', slug: 'troubleshooting', updated: '2026-10-13', title: 'Troubleshooting and Removal', description: 'Resolve Ping Warden setup, helper, Game Mode, Control Center, and latency problems. Collect diagnostics and safely remove the app.' },
  { source: 'Site/guides/updating-from-an-earlier-version.md', slug: 'updating-from-an-earlier-version', title: 'Updating from Ping Warden 2 or 3', updated: '2026-10-13', description: 'Updating to version 4 costs nothing and your protection keeps working. How the 90-day transition starts, what stays free, and what the $15 covers.' },
  { source: 'Site/guides/geforce-now-mac-stutter.md', slug: 'geforce-now-mac-stutter', updated: '2026-10-13', title: 'GeForce NOW Stutter on Mac: Causes and Fixes (AWDL, Wi-Fi)', description: 'GeForce NOW stuttering on your Mac over Wi-Fi? See how AWDL can contribute, how to test it in minutes, the free fixes, and what each one costs you.' },
  { source: 'Site/guides/awdl0-ping-spikes.md', slug: 'awdl0-ping-spikes', updated: '2026-09-25', title: 'Mac Wi-Fi Ping Spikes and the awdl0 Fix', description: "Investigate whether awdl0 contributes to Mac Wi-Fi ping spikes. Compare measurements, understand why the interface returns, and learn the sharing tradeoff." },
  { source: 'Site/guides/airdrop-wifi-lag.md', slug: 'airdrop-wifi-lag', updated: '2026-09-21', title: 'Is AirDrop Causing Your Wi-Fi Lag?', description: 'AirDrop is not moving files in the background, but the interface behind it can interrupt calls and remote sessions. Here is how to test it in a minute.' },
  { source: 'RELEASE_NOTES.md', slug: 'releases', updated: 'latest-release', title: 'Release Notes', description: 'Read the complete Ping Warden release history, including fixes, features, compatibility changes, and update details.' },
  { source: 'SECURITY.md', slug: 'security', updated: '2026-07-12', title: 'Security and Reporting', description: 'Learn which Ping Warden releases receive security support and how to report a vulnerability privately.' }
];
// The newest stable release in the signed Sparkle feed drives the version shown
// on the home page and the release-notes lastmod, so neither goes stale. Reading
// a committed file keeps the build deterministic.
const appcast = await readFile(resolve(root, 'appcast.xml'), 'utf8');
const releases = [...appcast.matchAll(/<item>([\s\S]*?)<\/item>/g)].map(([, item]) => ({
  build: Number(item.match(/<sparkle:version>(\d+)<\/sparkle:version>/)?.[1]),
  version: item.match(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/)?.[1],
  date: new Date(item.match(/<pubDate>([^<]+)<\/pubDate>/)?.[1] ?? NaN)
})).filter(r => r.build && r.version && !Number.isNaN(r.date.getTime()));
if (!releases.length) throw new Error('appcast.xml has no release with a version and pubDate');
const latest = releases.reduce((a, b) => (b.build > a.build ? b : a));
const latestVersion = latest.version;
const latestDate = latest.date.toISOString().slice(0, 10);
for (const page of pages) if (page.updated === 'latest-release') page.updated = latestDate;
// Tag Gumroad links so each site surface is its own referrer row in Gumroad
// Analytics (https://gumroad.com/help/article/270-url-parameters).
const gumroad = gumroadProduct;
function referred(href, referrer) {
  if (!href.startsWith(gumroad) || /[?&]referrer=/.test(href)) return href;
  const [base, anchor] = href.split('#');
  return `${base}${base.includes('?') ? '&' : '?'}referrer=${referrer}` + (anchor ? `#${anchor}` : '');
}
const bySource = new Map(pages.map(p => [p.source, `/docs/${p.slug}`]));
const escape = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const hashes = new Set();
function structured(value) {
  const json = JSON.stringify(value).replaceAll('<', '\\u003c');
  hashes.add(`'sha256-${createHash('sha256').update(json).digest('base64')}'`);
  return `<script type="application/ld+json">${json}</script>`;
}
const stylesheet = `/styles.css?v=${createHash('sha256').update(await readFile(resolve(output, 'styles.css'))).digest('hex').slice(0, 10)}`;
const icons = '<link rel="icon" href="/favicon.ico" sizes="48x48"><link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png"><link rel="apple-touch-icon" href="/apple-touch-icon.png">';
function head(title, description, path, schema) {
  return `<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} | Ping Warden</title><meta name="description" content="${escape(description)}">
<meta name="author" content="Oliver Ames"><meta name="theme-color" content="#ffffff">
<meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="${origin}${path}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Ping Warden">
<meta property="og:title" content="${escape(title)} | Ping Warden"><meta property="og:description" content="${escape(description)}">
<meta property="og:url" content="${origin}${path}"><meta property="og:image" content="${origin}/og.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="Ping Warden: stop Wi-Fi lag spikes in GeForce NOW and cloud gaming on Mac, with a latency graph showing spikes when protection is off">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${escape(title)} | Ping Warden"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${origin}/og.png">
${icons}<link rel="stylesheet" href="${stylesheet}">${structured(schema)}`;
}
const header = `<a class="skip" href="#main">Skip to content</a><header class="wrap"><a class="brand" href="/">Ping Warden</a><nav aria-label="Main navigation"><a href="/docs/">Docs</a><a href="/docs/setup">Setup</a><a href="${gumroad}?referrer=pingwarden-nav">Buy a license</a></nav></header>`;
const footer = `<footer class="wrap"><p>Ping Warden by Oliver Ames</p><nav aria-label="Resources"><a href="/">Website</a><a href="https://github.com/oliverames/ping-warden">Source</a><a href="mailto:oliver@ames.consulting">Support</a></nav></footer>`;
const nav = `<nav class="doc-nav" aria-label="Documentation">${pages.map(p => `<a href="/docs/${p.slug}">${escape(p.title)}</a>`).join('')}</nav>`;
const md = new MarkdownIt({ html: true, linkify: false });
function link(href, source) {
  if (href.startsWith(gumroad)) return referred(href, source.startsWith('Site/guides/') ? 'pingwarden-guide' : 'pingwarden-docs');
  if (/^(?:[a-z]+:|\/\/|#)/i.test(href)) return href;
  const [pathname, anchor] = href.split('#');
  const target = posix.normalize(posix.join(posix.dirname(source), pathname));
  const mapped = bySource.get(target);
  if (mapped) return mapped + (anchor ? `#${anchor}` : '');
  return `https://github.com/oliverames/ping-warden/blob/main/${target}` + (anchor ? `#${anchor}` : '');
}
const siteUpdated = '2026-10-13';
const urls = [{ loc: '/', lastmod: latestDate > siteUpdated ? latestDate : siteUpdated }, { loc: '/docs/', lastmod: siteUpdated }];
await mkdir(resolve(output, 'docs'), { recursive: true });
// Keep the website screenshot identical to the user-supplied version 4 capture.
await copyFile(resolve(root, 'docs/images/ping-warden-4-dashboard.png'), resolve(output, 'dashboard-v4.png'));
for (const page of pages) {
  const source = await readFile(resolve(root, page.source), 'utf8');
  // Omit repository badge blocks and its repeated title; all guide prose remains.
  let content = source.replace(/<p align="center">[\s\S]*?<\/p>/g, '').replace(/<h1[^>]*>[\s\S]*?<\/h1>/g, '');
  if (page.slug !== 'releases') content = content.replace(/^# .+\n/, '');
  const tokens = md.parse(content, {});
  const headings = [];
  const counts = new Map();
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.type === 'heading_open') {
      const text = tokens[i + 1].children.filter(t => t.type === 'text' || t.type === 'code_inline').map(t => t.content).join('');
      const slug = text.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, '').trim().replace(/\s/g, '-');
      const count = counts.get(slug) ?? 0;
      counts.set(slug, count + 1);
      const id = slug + (count ? `-${count}` : '');
      token.attrSet('id', id);
      // Release-note versions are h1s in the source; keep a single page h1.
      if (token.tag === 'h1') { token.tag = 'h2'; tokens[i + 2].tag = 'h2'; }
      if (token.tag === 'h2') headings.push({ text, id });
    }
    for (const child of token.children ?? []) {
      if (child.type === 'link_open') child.attrSet('href', link(child.attrGet('href'), page.source));
    }
  }
  const path = `/docs/${page.slug}`;
  urls.push({ loc: path, lastmod: page.updated });
  const schema = { '@context': 'https://schema.org', '@graph': [
    { '@type': 'TechArticle', headline: page.title, description: page.description, url: origin + path, dateModified: page.updated, author: { '@type': 'Person', name: 'Oliver Ames' }, publisher, inLanguage: 'en' },
    { '@type': 'BreadcrumbList', itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'Ping Warden', item: origin + '/' },
      { '@type': 'ListItem', position: 2, name: 'Documentation', item: origin + '/docs/' },
      { '@type': 'ListItem', position: 3, name: page.title, item: origin + path }
    ] }
  ] };
  const toc = headings.length ? `<details class="toc"><summary>On this page</summary><ol>${headings.map(h => `<li><a href="#${escape(h.id)}">${escape(h.text)}</a></li>`).join('')}</ol></details>` : '';
  const html = `<!doctype html><html lang="en"><head>${head(page.title, page.description, path, schema)}</head><body>${header}<main id="main" class="wrap doc-layout"><aside>${nav}</aside><article class="prose"><p class="breadcrumb"><a href="/docs/">Documentation</a></p><h1>${escape(page.title)}</h1><p class="doc-intro">${escape(page.description)}</p>${toc}${md.renderer.render(tokens, md.options, {})}<p class="source-note"><a href="https://github.com/oliverames/ping-warden/blob/main/${page.source}">View this guide on GitHub</a></p></article></main>${footer}</body></html>\n`;
  await writeFile(resolve(output, `docs/${page.slug}.html`), html);
}
const hubTitle = 'Documentation';
const hubDescription = 'The complete Ping Warden documentation: setup, features, pricing, privacy, technical notes, troubleshooting, security, and release history.';
await writeFile(resolve(output, 'docs/index.html'), `<!doctype html><html lang="en"><head>${head(hubTitle, hubDescription, '/docs/', { '@context': 'https://schema.org', '@type': 'CollectionPage', name: 'Ping Warden Documentation', url: origin + '/docs/', description: hubDescription })}</head><body>${header}<main id="main" class="wrap docs-index"><h1>Everything you need<br>to know.</h1><p class="intro">From your first install to the details of how Ping Warden works.</p><div class="doc-list">${pages.map(p => `<article><h2><a href="/docs/${p.slug}">${escape(p.title)}</a></h2><p>${escape(p.description)}</p></article>`).join('')}</div></main>${footer}</body></html>\n`);
const appSchema = { '@context': 'https://schema.org', '@graph': [
  { '@type': 'WebSite', '@id': origin + '/#website', name: 'Ping Warden', url: origin + '/', inLanguage: 'en' },
  { '@type': 'SoftwareApplication', name: 'Ping Warden', url: origin + '/', operatingSystem: 'macOS 13 or later', softwareVersion: latestVersion, applicationCategory: 'UtilitiesApplication', image: origin + '/app-icon.png', screenshot: origin + '/dashboard-v4.png', description: 'A macOS menu bar app that monitors latency and pauses AWDL to reduce related Wi-Fi interruptions. The dashboard is free; enabling Ping Protection requires a one-time $15 license.', author: { '@type': 'Person', name: 'Oliver Ames' }, publisher, sameAs: [githubRepo, gumroadProduct], downloadUrl: 'https://github.com/oliverames/ping-warden/releases/latest', softwareHelp: { '@type': 'WebPage', url: origin + '/docs/' }, offers: [
    { '@type': 'Offer', name: 'Free dashboard', price: '0', priceCurrency: 'USD', availability: 'https://schema.org/InStock', url: 'https://github.com/oliverames/ping-warden/releases/latest' },
    { '@type': 'Offer', name: 'Ping Protection license', price: '15', priceCurrency: 'USD', availability: 'https://schema.org/InStock', url: gumroadProduct }
  ] }
] };
const styled = html => html.replace(/href="\/styles\.css(?:\?v=[0-9a-f]+)?"/g, `href="${stylesheet}"`);
const home = (await readFile(resolve(site, 'home.html'), 'utf8'))
  .replace('<!-- structured-data -->', structured(appSchema))
  .replaceAll('<!-- latest-version -->', escape(latestVersion));
await writeFile(resolve(output, 'index.html'), styled(home));
const notFound = (await readFile(resolve(site, '404.html'), 'utf8'))
  .replace('<!-- header -->', header).replace('<!-- footer -->', footer);
await writeFile(resolve(output, '404.html'), styled(notFound));
await writeFile(resolve(output, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map(u => `  <url><loc>${origin}${u.loc}</loc><lastmod>${u.lastmod}</lastmod></url>`).join('\n')}\n</urlset>\n`);
// Static images and the versioned stylesheet may be cached for a day. HTML keeps
// the platform default (revalidate every time) so deploys show up immediately.
// Images are listed by exact path because their names are not fingerprinted.
const images = (await readdir(output)).filter(f => /\.(?:png|webp|ico)$/.test(f)).sort();
const cached = [...images.map(f => `/${f}`), '/styles.css'].map(p => `${p}\n  Cache-Control: public, max-age=86400\n`).join('');
await writeFile(resolve(output, '_headers'), `/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n  Cross-Origin-Opener-Policy: same-origin\n  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; script-src ${[...hashes].join(' ')}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\n${cached}`);
console.log(`Built ${urls.length} pages from the complete repository guides.`);
