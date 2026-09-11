import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve, relative, posix } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import MarkdownIt from 'markdown-it';

const site = dirname(fileURLToPath(import.meta.url));
const root = resolve(site, '..');
const output = resolve(site, 'public');
const origin = 'https://pingwarden.app';
const pages = [
  { source: 'README.md', slug: 'overview', title: 'Features, Pricing, and Privacy', description: 'Explore Ping Warden features, the $15 Ping Protection license, the existing-user transition, privacy, system requirements, and source builds.' },
  { source: 'PingWarden/QUICKSTART.md', slug: 'setup', title: 'Setup Guide', description: 'Install Ping Warden, activate your license, approve the helper, and verify Ping Protection. Set up Game Mode, latency targets, and Control Center.' },
  { source: 'PingWarden/README.md', slug: 'technical', title: 'Technical Documentation', description: 'How Ping Warden works: AWDL events, the privileged helper, XPC, latency measurement, automation, security, diagnostics, and signed updates.' },
  { source: 'PingWarden/TROUBLESHOOTING.md', slug: 'troubleshooting', title: 'Troubleshooting and Removal', description: 'Resolve Ping Warden setup, helper, Game Mode, Control Center, and latency problems. Collect diagnostics and safely remove the app.' },
  { source: 'Site/guides/geforce-now-mac-stutter.md', slug: 'geforce-now-mac-stutter', title: 'Why GeForce NOW Stutters on a MacBook', description: 'Periodic stutter in GeForce NOW on a Mac is often the awdl0 interface. Here is how to confirm it in 30 seconds, the free fixes, and what you give up.' },
  { source: 'Site/guides/awdl0-ping-spikes.md', slug: 'awdl0-ping-spikes', title: 'awdl0 Ping Spikes on macOS', description: "The awdl0 interface shares your Mac's Wi-Fi radio and can cause periodic ping spikes. How to measure it, why it comes back, and what suppressing it costs." },
  { source: 'Site/guides/airdrop-wifi-lag.md', slug: 'airdrop-wifi-lag', title: 'Is AirDrop Causing Your Wi-Fi Lag?', description: 'AirDrop is not moving files in the background, but the interface behind it can interrupt calls and remote sessions. Here is how to test it in a minute.' },
  { source: 'RELEASE_NOTES.md', slug: 'releases', title: 'Release Notes', description: 'Read the complete Ping Warden release history, including fixes, features, compatibility changes, and update details.' },
  { source: 'SECURITY.md', slug: 'security', title: 'Security and Reporting', description: 'Learn which Ping Warden releases receive security support and how to report a vulnerability privately.' }
];
const bySource = new Map(pages.map(p => [p.source, `/docs/${p.slug}`]));
const escape = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const hashes = new Set();
function structured(value) {
  const json = JSON.stringify(value).replaceAll('<', '\\u003c');
  hashes.add(`'sha256-${createHash('sha256').update(json).digest('base64')}'`);
  return `<script type="application/ld+json">${json}</script>`;
}
function head(title, description, path, schema) {
  return `<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} | Ping Warden</title><meta name="description" content="${escape(description)}">
<meta name="author" content="Oliver Ames"><meta name="theme-color" content="#ffffff">
<meta name="robots" content="index,follow,max-image-preview:large"><link rel="canonical" href="${origin}${path}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Ping Warden">
<meta property="og:title" content="${escape(title)} | Ping Warden"><meta property="og:description" content="${escape(description)}">
<meta property="og:url" content="${origin}${path}"><meta property="og:image" content="${origin}/app-icon.png"><meta property="og:image:alt" content="Ping Warden app icon">
<meta name="twitter:card" content="summary"><meta name="twitter:title" content="${escape(title)} | Ping Warden"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${origin}/app-icon.png">
<link rel="icon" type="image/png" href="/app-icon.png"><link rel="stylesheet" href="/styles.css">${structured(schema)}`;
}
const header = `<a class="skip" href="#main">Skip to content</a><header class="wrap"><a class="brand" href="/">Ping Warden</a><nav aria-label="Main navigation"><a href="/docs/">Docs</a><a href="/docs/setup">Setup</a><a href="https://amesconsulting.gumroad.com/l/pingwarden">Buy a license</a></nav></header>`;
const footer = `<footer class="wrap"><p>Ping Warden by Oliver Ames</p><nav aria-label="Resources"><a href="/">Website</a><a href="https://github.com/oliverames/ping-warden">Source</a><a href="mailto:oliver@ames.consulting">Support</a></nav></footer>`;
const nav = `<nav class="doc-nav" aria-label="Documentation">${pages.map(p => `<a href="/docs/${p.slug}">${escape(p.title)}</a>`).join('')}</nav>`;
const md = new MarkdownIt({ html: true, linkify: false });
function link(href, source) {
  if (/^(?:[a-z]+:|\/\/|#)/i.test(href)) return href;
  const [pathname, anchor] = href.split('#');
  const target = posix.normalize(posix.join(posix.dirname(source), pathname));
  const mapped = bySource.get(target);
  if (mapped) return mapped + (anchor ? `#${anchor}` : '');
  return `https://github.com/oliverames/ping-warden/blob/main/${target}` + (anchor ? `#${anchor}` : '');
}
const urls = ['/', '/docs/'];
await mkdir(resolve(output, 'docs'), { recursive: true });
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
  urls.push(path);
  const schema = { '@context': 'https://schema.org', '@graph': [
    { '@type': 'TechArticle', headline: page.title, description: page.description, url: origin + path, author: { '@type': 'Person', name: 'Oliver Ames' }, inLanguage: 'en' },
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
  { '@type': 'SoftwareApplication', name: 'Ping Warden', url: origin + '/', operatingSystem: 'macOS 13 or later', applicationCategory: 'UtilitiesApplication', image: origin + '/app-icon.png', screenshot: origin + '/dashboard.png', description: 'A macOS menu bar app that monitors latency and pauses AWDL to reduce related Wi-Fi interruptions. The dashboard is free; enabling Ping Protection requires a one-time $15 license.', author: { '@type': 'Person', name: 'Oliver Ames' }, downloadUrl: 'https://github.com/oliverames/ping-warden/releases/latest', softwareHelp: { '@type': 'WebPage', url: origin + '/docs/' }, offers: [
    { '@type': 'Offer', name: 'Free dashboard', price: '0', priceCurrency: 'USD', url: 'https://github.com/oliverames/ping-warden/releases/latest' },
    { '@type': 'Offer', name: 'Ping Protection license', price: '15', priceCurrency: 'USD', url: 'https://amesconsulting.gumroad.com/l/pingwarden' }
  ] }
] };
await writeFile(resolve(output, 'index.html'), (await readFile(resolve(site, 'home.html'), 'utf8')).replace('<!-- structured-data -->', structured(appSchema)));
await writeFile(resolve(output, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map(path => `  <url><loc>${origin}${path}</loc></url>`).join('\n')}\n</urlset>\n`);
await writeFile(resolve(output, '_headers'), `/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; script-src ${[...hashes].join(' ')}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\n`);
console.log(`Built ${urls.length} pages from the complete repository guides.`);
