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
