#!/usr/bin/env python3
"""Validate generated pages, structured data, local navigation, and crawl metadata."""
from html.parser import HTMLParser
from datetime import datetime, timedelta, timezone
import json
import re
from pathlib import Path
from urllib.parse import urlsplit, unquote
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent / 'public'

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.ids, self.links, self.assets = path, [], [], []
        self.canonicals, self.descriptions, self.h1s = [], [], 0
        self.scripts, self.script, self.title, self.in_title = [], None, '', False
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag == 'a': self.links.append(a.get('href', ''))
        if tag == 'h1': self.h1s += 1
        if tag == 'title': self.in_title = True
        if tag == 'meta' and a.get('name') == 'description': self.descriptions.append(a.get('content'))
        if tag == 'link' and a.get('rel') == 'canonical': self.canonicals.append(a['href'])
        if tag == 'link' and a.get('rel') in ('stylesheet', 'icon', 'apple-touch-icon'): self.assets.append(a['href'])
        if tag == 'source' and 'srcset' in a:
            self.assets.extend(c.split()[0] for c in a['srcset'].split(',') if c.strip())
        if tag == 'img':
            assert 'alt' in a and 'width' in a and 'height' in a, (self.path, 'image metadata')
            self.assets.append(a['src'])
        if tag == 'script':
            assert a.get('type') == 'application/ld+json', 'Unexpected executable script'
            self.script = ''

    def handle_data(self, data):
        if self.script is not None: self.script += data
        if self.in_title: self.title += data

    def handle_endtag(self, tag):
        if tag == 'script':
            self.scripts.append(json.loads(self.script))
            self.script = None
        if tag == 'title': self.in_title = False

pages = {p: Page(p) for p in root.rglob('*.html')}

def target(url, current):
    parsed = urlsplit(url)
    if parsed.scheme and parsed.netloc != 'pingwarden.app': return None, None
    path = unquote(parsed.path)
    if not path: return current, unquote(parsed.fragment)
    result = root / path.lstrip('/') if path.startswith('/') else current.parent / path
    if result.is_dir(): result /= 'index.html'
    elif not result.suffix: result = result.with_suffix('.html')
    return result, unquote(parsed.fragment)

canonical_urls, titles = set(), set()
for path, page in pages.items():
    assert page.h1s == 1, (path, 'Expected one h1', page.h1s)
    assert len(page.ids) == len(set(page.ids)), (path, 'Duplicate IDs')
    assert page.title and page.title not in titles, (path, 'Duplicate or missing title')
    titles.add(page.title)
    if path.name != '404.html':
        assert len(page.descriptions) == 1 and 50 <= len(page.descriptions[0]) <= 180, (path, 'Description')
        assert len(page.canonicals) == 1 and page.canonicals[0] not in canonical_urls, (path, 'Canonical')
        canonical_urls.update(page.canonicals)
        assert page.scripts, (path, 'Missing structured data')
        assert target(page.canonicals[0], path)[0] == path, (path, 'Canonical route mismatch')
    for url in page.links + page.assets:
        dest, fragment = target(url, path)
        if dest is None: continue
        assert dest.is_file(), (path, 'Broken local link', url)
        if fragment: assert dest in pages and fragment in pages[dest].ids, (path, 'Broken anchor', url)

home = (root / 'index.html').read_text()
assert '<!-- latest-version -->' not in home and '<!-- structured-data -->' not in home, 'Unfilled home placeholder'

sitemap = ET.parse(root / 'sitemap.xml')
locations = [e.text for e in sitemap.findall('.//{*}loc')]
assert len(locations) == len(set(locations)), 'Duplicate sitemap URLs'
assert set(locations) == canonical_urls, 'Sitemap does not match canonical pages'
assert 'Sitemap: https://pingwarden.app/sitemap.xml' in (root / 'robots.txt').read_text()
assert 'Disallow: /' not in (root / 'robots.txt').read_text()

# RFC 9116 security.txt: contacts, a future Expires within a year, and a canonical URL.
security = (root / '.well-known' / 'security.txt').read_text()
fields = [line.split(': ', 1) for line in security.splitlines() if line and not line.startswith('#')]
def field(name): return [value for key, value in fields if key == name]
assert len(field('Contact')) >= 1 and all(c.startswith(('https://', 'mailto:')) for c in field('Contact')), 'security.txt Contact'
assert field('Canonical') == ['https://pingwarden.app/.well-known/security.txt'], 'security.txt Canonical'
assert len(field('Expires')) == 1, 'security.txt Expires'
expires = datetime.fromisoformat(field('Expires')[0].replace('Z', '+00:00'))
now = datetime.now(timezone.utc)
assert now < expires <= now + timedelta(days=366), f'security.txt Expires must be in the future and under a year out (found {expires:%Y-%m-%d}); renew it'
assert target(field('Policy')[0], root / 'index.html')[0] in pages, 'security.txt Policy page'

# Structured data: article freshness, publisher, and availability on the product offers.
graphs = {id(s): s for page in pages.values() for s in page.scripts}
nodes = [n for s in graphs.values() for n in (s.get('@graph') or [s])]
articles = [n for n in nodes if n.get('@type') == 'TechArticle']
assert len(articles) == len([p for p in pages if p.parent.name == 'docs' and p.name != 'index.html']), 'TechArticle per guide'
for a in articles:
    assert re.fullmatch(r'\d{4}-\d{2}-\d{2}', a.get('dateModified', '')), (a['url'], 'dateModified')
    assert a.get('publisher', {}).get('name') == 'Ames Consulting LLC', (a['url'], 'publisher')
modified = {a['url']: a['dateModified'] for a in articles}
for e in sitemap.findall('.//{*}url'):
    loc, lastmod = e.find('{*}loc').text, e.find('{*}lastmod').text
    if loc in modified: assert modified[loc] == lastmod, (loc, 'sitemap lastmod differs from dateModified')
app = next(n for n in nodes if n.get('@type') == 'SoftwareApplication')
assert app['publisher']['name'] == 'Ames Consulting LLC' and len(app['sameAs']) == 2, 'SoftwareApplication publisher/sameAs'
assert all(o['availability'] == 'https://schema.org/InStock' for o in app['offers']), 'Offer availability'
assert not any(k in json.dumps(nodes) for k in ('aggregateRating', '"Review"')), 'No rating or review markup'

assert 'Plus VAT or sales tax where applicable.' in home, 'Home price tax note'

# The 404 page carries the site navigation and points readers at help.
missing = pages[root / '404.html'].links
assert all(href in missing for href in ('/', '/docs/', '/docs/setup', '/docs/troubleshooting', 'mailto:oliver@ames.consulting')), '404 navigation'

# GeForce NOW guide metadata stays within search-snippet limits.
gfn = pages[root / 'docs' / 'geforce-now-mac-stutter.html']
assert len(gfn.title.split(' | ')[0]) <= 60 and len(gfn.descriptions[0]) <= 155, 'GeForce NOW title/description length'
assert not any(p.suffix in ('.md', '.mjs', '.jsonc', '.map') for p in root.rglob('*') if p.is_file()), 'Build source exposed'
print(f'Validated {len(pages)} HTML pages, structured JSON, all local links and anchors, and {len(locations)} sitemap URLs.')
