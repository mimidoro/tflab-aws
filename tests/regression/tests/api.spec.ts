import { expect, test } from '@playwright/test';

// API regression. Adapts to the region it hits: a writable primary must support full CRUD,
// a read-only standby must refuse writes with 503 (proves failover semantics are correct).

test.describe('health', () => {
  test('liveness returns ok', async ({ request }) => {
    const res = await request.get('/api/healthz');
    expect(res.status()).toBe(200);
    expect(await res.json()).toEqual({ status: 'ok' });
  });

  test('readiness reports database reachable', async ({ request }) => {
    const res = await request.get('/api/ready');
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.db).toBe('ok');
    expect(typeof body.writable).toBe('boolean');
  });

  test('info identifies the serving region and pod', async ({ request }) => {
    const res = await request.get('/api/info');
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.region).toMatch(/Sydney|Melbourne/);
    expect(body.pod).toMatch(/^api-/);
    expect(['primary', 'standby']).toContain(body.configuredRole);
  });
});

test.describe('items', () => {
  test('list returns an array', async ({ request }) => {
    const res = await request.get('/api/items');
    expect(res.status()).toBe(200);
    expect(Array.isArray(await res.json())).toBe(true);
  });

  test('rejects empty text with 400', async ({ request }) => {
    const res = await request.post('/api/items', { data: { text: '   ' } });
    expect(res.status()).toBe(400);
  });

  test('rejects text over 200 characters with 400', async ({ request }) => {
    const res = await request.post('/api/items', { data: { text: 'x'.repeat(201) } });
    expect(res.status()).toBe(400);
  });

  test('unknown item returns 404', async ({ request }) => {
    const res = await request.get('/api/items/999999999');
    expect(res.status()).toBe(404);
  });

  test('create, read, delete round trip (or 503 on read-only standby)', async ({ request }) => {
    const info = await (await request.get('/api/info')).json();
    const text = `regression-${Date.now()}`;
    const created = await request.post('/api/items', { data: { text } });

    if (info.dbWritable === false) {
      expect(created.status()).toBe(503);
      return;
    }

    expect(created.status()).toBe(201);
    const item = await created.json();
    expect(item.text).toBe(text);

    const fetched = await request.get(`/api/items/${item.id}`);
    expect(fetched.status()).toBe(200);
    expect((await fetched.json()).id).toBe(item.id);

    const deleted = await request.delete(`/api/items/${item.id}`);
    expect(deleted.status()).toBe(204);

    const gone = await request.get(`/api/items/${item.id}`);
    expect(gone.status()).toBe(404);
  });
});

test.describe('edge', () => {
  test('HTTP redirects to HTTPS', async ({ request, baseURL }) => {
    const httpUrl = baseURL!.replace('https://', 'http://') + '/api/healthz';
    const res = await request.get(httpUrl, { maxRedirects: 0 });
    expect(res.status()).toBe(301);
    expect(res.headers()['location']).toMatch(/^https:\/\//);
  });
});
