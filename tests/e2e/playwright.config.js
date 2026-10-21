const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  timeout: 60_000,
  retries: 0,
  workers: 1,
  use: { baseURL: 'http://app.test', screenshot: 'only-on-failure', trace: 'retain-on-failure' },
});
