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

test('the landing header sticks, tracks the active section, and animates its progress', async ({ page }) => {
  const consoleErrors = watchConsole(page);

  await page.goto('/');
  const header = page.locator('.mkt-nav');
  await expect(header).toHaveCSS('position', 'fixed');
  await expect(header).not.toHaveClass(/is-scrolled/);

  await page.locator('#inside').scrollIntoViewIfNeeded();
  await expect(header).toHaveClass(/is-scrolled/);
  await expect(page.locator('.mkt-nav-links a[href="#inside"]')).toHaveClass(/active/);

  const progress = await page.locator('.mkt-progress i').evaluate((element) => getComputedStyle(element).transform);
  expect(progress).not.toBe('matrix(0, 0, 0, 1, 0, 0)');

  expect(consoleErrors).toEqual([]);
});

test('the mobile menu opens, navigates to a section, and closes', async ({ page }) => {
  const consoleErrors = watchConsole(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');

  const openButton = page.getByRole('button', { name: 'Open menu' });
  await expect(openButton).toBeVisible();
  await openButton.click();

  const mobileNav = page.getByRole('navigation', { name: 'Mobile product navigation' });
  await expect(mobileNav).toBeVisible();
  await expect(page.locator('.mkt-menu-button')).toHaveAttribute('aria-expanded', 'true');
  await mobileNav.getByRole('link', { name: 'How it works' }).click();

  await expect(page).toHaveURL(/#how$/);
  await expect(page.getByRole('heading', { name: 'Set up the record in three moves.' })).toBeInViewport();
  await expect(mobileNav).toBeHidden();
  await expect(page.locator('.mkt-menu-button')).toHaveAttribute('aria-expanded', 'false');

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
