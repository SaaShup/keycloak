const { test, expect } = require('@playwright/test');

const USER = 'saashup';
const PASSWORD = 'saashup';

async function keycloakLogin(page) {
  await page.fill('#username', USER);
  await page.fill('#password', PASSWORD);
  await page.click('#kc-login');
}

// Keycloak shows "Invalid parameter: post_logout_redirect_uri" (or similar)
// on its own error page when the post-logout URI is not whitelisted.
async function expectNoKeycloakError(page) {
  await expect(page.locator('#kc-error-message')).toHaveCount(0);
  await expect(page.locator('body')).not.toContainText(/invalid (redirect|parameter)/i);
}

test('saashup: login then logout returns to the app and ends the SSO session', async ({ page }) => {
  await page.goto('/');
  await page.waitForURL(/\/auth\/realms\/paashup\//);
  await keycloakLogin(page);
  await expect(page).toHaveURL('http://app.test/');
  await expect(page.locator('body')).toContainText('contact@saashup.com');

  await page.goto('/logout');
  await expectNoKeycloakError(page);
  // redirected back to saashup, which then asks to log in again
  await page.waitForURL(/\/auth\/realms\/paashup\/protocol\/openid-connect\/auth/);
  await expect(page.locator('#username')).toBeVisible();
});

test('grafana: login through keycloak, then logout returns to grafana login', async ({ page }) => {
  await page.goto('/dashboard/login');
  await page.getByRole('link', { name: /sign in with keycloak/i }).click();
  await page.waitForURL(/\/auth\/realms\/paashup\//);
  await keycloakLogin(page);
  await expect(page).toHaveURL(/^http:\/\/app\.test\/dashboard\//);
  await expect(page).not.toHaveURL(/\/login/);

  await page.goto('/dashboard/logout');
  await expectNoKeycloakError(page);
  await expect(page).toHaveURL('http://app.test/dashboard/login');

  // SSO session is gone: going through keycloak again asks for credentials
  await page.getByRole('link', { name: /sign in with keycloak/i }).click();
  await expect(page.locator('#username')).toBeVisible();
});
