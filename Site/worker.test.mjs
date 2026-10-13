import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';

test('www redirects preserve path and query on the canonical HTTPS domain', async () => {
  const response = await worker.fetch(new Request('https://www.pingwarden.app/docs/setup?from=app'), {});
  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://pingwarden.app/docs/setup?from=app');
});

test('canonical asset responses keep status, content and headers', async () => {
  const response = await worker.fetch(new Request('https://pingwarden.app/missing'), {
    ASSETS: { fetch: async () => new Response('Not found', { status: 404, headers: { 'X-Content-Type-Options': 'nosniff' } }) }
  });
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not found');
  assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
});

test('plain HTTP redirects to HTTPS and preserves path and query', async () => {
  const response = await worker.fetch(new Request('http://pingwarden.app/docs/setup?from=app'), {});
  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://pingwarden.app/docs/setup?from=app');
});

test('plain HTTP on www redirects once to the canonical HTTPS domain', async () => {
  const response = await worker.fetch(new Request('http://www.pingwarden.app/'), {});
  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://pingwarden.app/');
});

test('HTTPS canonical requests are served without a redirect', async () => {
  const response = await worker.fetch(new Request('https://pingwarden.app/'), {
    ASSETS: { fetch: async () => new Response('home', { status: 200 }) }
  });
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'home');
});

test('local development over HTTP is not redirected', async () => {
  const response = await worker.fetch(new Request('http://localhost:8787/'), {
    ASSETS: { fetch: async () => new Response('home', { status: 200 }) }
  });
  assert.equal(response.status, 200);
});

test('the retired dashboard.png address redirects to the current screenshot', async () => {
  const response = await worker.fetch(new Request('https://pingwarden.app/dashboard.png'), {});
  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://pingwarden.app/dashboard-v4.png');
});
