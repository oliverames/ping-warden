#!/usr/bin/env python3
"""Validate generated pages, structured data, local navigation, and crawl metadata."""
from html.parser import HTMLParser
import json
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
        if tag == 'link' and a.get('rel') in ('stylesheet', 'icon'): self.assets.append(a['href'])
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

sitemap = ET.parse(root / 'sitemap.xml')
locations = [e.text for e in sitemap.findall('.//{*}loc')]
assert len(locations) == len(set(locations)), 'Duplicate sitemap URLs'
assert set(locations) == canonical_urls, 'Sitemap does not match canonical pages'
assert 'Sitemap: https://pingwarden.app/sitemap.xml' in (root / 'robots.txt').read_text()
assert 'Disallow: /' not in (root / 'robots.txt').read_text()
assert not any(p.suffix in ('.md', '.mjs', '.jsonc', '.map') for p in root.rglob('*') if p.is_file()), 'Build source exposed'
print(f'Validated {len(pages)} HTML pages, structured JSON, all local links and anchors, and {len(locations)} sitemap URLs.')
