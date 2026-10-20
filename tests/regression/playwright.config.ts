import { defineConfig, devices } from '@playwright/test';

// BASE_URL picks the target:
//   https://app.mimidog.click  (default) - whichever region Route 53 is serving
//   https://syd.mimidog.click            - Sydney only
//   https://mel.mimidog.click            - Melbourne only
const baseURL = process.env.BASE_URL ?? 'https://app.mimidog.click';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never' }], ['junit', { outputFile: 'results/junit.xml' }]],
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'api', testMatch: /api\.spec\.ts/ },
    { name: 'ui', testMatch: /ui\.spec\.ts/, use: { ...devices['Desktop Chrome'] } },
  ],
});
