import { expect, test, type Page } from '@playwright/test';

function watchConsole(page: Page) {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  return errors;
}

test('the marketing page tells the product story and links into sign-in', async ({ page }) => {
  const consoleErrors = watchConsole(page);

  await page.goto('/');
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { level: 1, name: 'The chama remembers.' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Everything the committee carries, in one place.' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Your money never passes through us.' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Start your chama' }).first()).toHaveAttribute('href', '/login');
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toHaveCount(0);

  await page.getByRole('link', { name: 'See how the ledger works' }).click();
  await expect(page).toHaveURL(/#ledger$/);
  await expect(page.getByRole('heading', { name: 'A chama runs on trust. Trust runs on a record.' })).toBeInViewport();

  expect(consoleErrors).toEqual([]);
});

test('the app and login URLs are separated cleanly', async ({ page }) => {
  const consoleErrors = watchConsole(page);

  await page.goto('/app');
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('heading', { name: 'Karibu' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Back to Chama Ledger' })).toBeVisible();

  await page.goto('/login');
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole('heading', { name: 'Karibu' })).toBeVisible();

  await page.getByRole('link', { name: 'Back to Chama Ledger' }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { level: 1, name: 'The chama remembers.' })).toBeVisible();

  expect(consoleErrors).toEqual([]);
});
