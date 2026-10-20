import { expect, test } from '@playwright/test';

test.describe('front end', () => {
  test('home page renders and shows the serving region', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'tflab-aws' })).toBeVisible();
    await expect(page.getByTestId('region')).toHaveText(/Sydney|Melbourne/);
    await expect(page.getByTestId('db-mode')).not.toHaveText('unreachable');
  });

  test('security headers are present', async ({ request }) => {
    const res = await request.get('/');
    expect(res.status()).toBe(200);
    const h = res.headers();
    expect(h['x-content-type-options']).toBe('nosniff');
    expect(h['x-frame-options']).toBe('DENY');
    expect(h['content-security-policy']).toContain("default-src 'self'");
  });

  test('deep links fall back to the SPA', async ({ page }) => {
    const res = await page.goto('/some/deep/link');
    expect(res?.status()).toBe(200);
    await expect(page.getByRole('heading', { name: 'tflab-aws' })).toBeVisible();
  });

  test('adding an item shows it in the list (or the standby message)', async ({ page, request }) => {
    await page.goto('/');
    const mode = await page.getByTestId('db-mode').textContent();
    const text = `ui-regression-${Date.now()}`;

    await page.getByTestId('item-input').fill(text);
    await page.getByTestId('item-submit').click();

    if (mode === 'read-only standby') {
      await expect(page.getByTestId('error')).toContainText('read-only standby');
      return;
    }

    await expect(page.getByTestId('item-list')).toContainText(text);

    // Clean up through the API so repeated runs don't grow the table.
    const items: Array<{ id: number; text: string }> = await (await request.get('/api/items')).json();
    const mine = items.find((i) => i.text === text);
    if (mine) await request.delete(`/api/items/${mine.id}`);
  });
});
