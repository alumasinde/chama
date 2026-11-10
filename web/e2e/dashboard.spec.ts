import { expect, test, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { openAs, selectGroup } from './support';

const PIN = process.env.E2E_PIN || '4826';

function watchConsole(page: Page) {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  return errors;
}

test('admin uses a reused session to download reports and inspect the audit diff', async ({ page }) => {
  const consoleErrors = watchConsole(page);
  await openAs(page, 'admin');
  await selectGroup(page);

  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe('#/overview');
  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  await expect(nav.getByRole('button', { name: 'Reports', exact: true })).toBeVisible();
  await expect(nav.getByRole('button', { name: 'Audit log', exact: true })).toBeVisible();
  await nav.getByRole('button', { name: 'Reports', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible();

  await page.getByRole('button', { name: /^Exports/ }).click();
  const transactionsCard = page.locator('.export-card').filter({ hasText: 'Transactions' });
  await expect(transactionsCard).toBeVisible();

  const [csv] = await Promise.all([
    page.waitForEvent('download'),
    transactionsCard.getByRole('button', { name: 'CSV', exact: true }).click(),
  ]);
  expect(csv.suggestedFilename()).toMatch(/\.csv$/);
  const csvPath = await csv.path();
  expect(csvPath).toBeTruthy();
  const csvBytes = readFileSync(csvPath as string);
  expect(csvBytes.subarray(0, 3)).toEqual(Buffer.from([0xef, 0xbb, 0xbf]));

  const [pdf] = await Promise.all([
    page.waitForEvent('download'),
    transactionsCard.getByRole('button', { name: 'PDF', exact: true }).click(),
  ]);
  expect(pdf.suggestedFilename()).toMatch(/\.pdf$/);
  const pdfPath = await pdf.path();
  expect(pdfPath).toBeTruthy();
  expect(readFileSync(pdfPath as string).subarray(0, 4).toString()).toBe('%PDF');

  await nav.getByRole('button', { name: 'Audit log', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Audit log' })).toBeVisible();
  await page.locator('tbody tr.clickable').first().click();

  const drawer = page.getByRole('dialog', { name: 'Audit entry detail' });
  await expect(drawer).toBeVisible();
  await expect(drawer.getByText('Field changes')).toBeVisible();
  await expect(drawer.locator('.diff-head')).toContainText('Before');
  await expect(drawer.locator('.diff-head')).toContainText('After');
  await expect(drawer.locator('.diff-row')).not.toHaveCount(0);
  expect(consoleErrors).toEqual([]);
});

test('member gets a read-only overview without committee navigation', async ({ page }) => {
  const consoleErrors = watchConsole(page);
  await openAs(page, 'member');
  await selectGroup(page);

  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  await expect(page.getByRole('heading', { name: 'Your chama at a glance' })).toBeVisible();
  await expect(page.getByText('Member view')).toBeVisible();
  await expect(page.getByText('Your rotation position')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Your personal ledger' })).toBeVisible();

  await expect(nav.getByRole('button', { name: 'Reports', exact: true })).toHaveCount(0);
  await expect(nav.getByRole('button', { name: 'Audit log', exact: true })).toHaveCount(0);
  await expect(nav.getByRole('button', { name: 'Members', exact: true })).toHaveCount(0);
  await expect(nav.getByRole('button', { name: 'M-Pesa settings', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Record payment', exact: true })).toHaveCount(0);
  await expect(page.getByText('This view is read-only.', { exact: false })).toBeVisible();
  expect(consoleErrors).toEqual([]);
});

test('committee approves a welfare claim and records a PIN-protected payout', async ({ page }) => {
  const consoleErrors = watchConsole(page);
  await openAs(page, 'admin');
  await selectGroup(page);

  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  await nav.getByRole('button', { name: 'Welfare', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Welfare' })).toBeVisible();

  const reason = `E2E welfare claim ${Date.now()}`;
  await page.getByRole('button', { name: 'Request support', exact: true }).first().click();
  const request = page.getByRole('dialog', { name: 'Request welfare support' });
  await request.locator('#w-claim-amount').fill('1.00');
  await request.locator('#w-reason').fill(reason);
  await request.getByRole('button', { name: 'Send request' }).click();
  await expect(page.getByText('Claim sent to the committee.')).toBeVisible();

  await page.locator('.tab').filter({ hasText: 'Claims' }).click();
  const row = page.locator('tbody tr').filter({ hasText: reason });
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Review' }).click();

  const review = page.getByRole('dialog', { name: 'Review welfare claim' });
  await review.locator('#w-decision').selectOption('approved');
  await review.locator('#w-comment').fill('Approved by the browser test.');
  await review.getByRole('button', { name: 'Record decision' }).click();
  await expect(page.getByText('Claim approved.')).toBeVisible();

  await expect(row.getByRole('button', { name: 'Pay claim' })).toBeVisible();
  await row.getByRole('button', { name: 'Pay claim' }).click();
  const payout = page.getByRole('dialog', { name: 'Record welfare payout' });
  await payout.locator('#w-pay-ref').fill(`E2E-PAYOUT-${Date.now()}`);
  await payout.getByRole('button', { name: 'Continue' }).click();

  await expect(page.locator('#step-pin')).toBeVisible();
  await page.locator('#step-pin').fill(PIN);
  await page.getByRole('button', { name: 'Confirm welfare entry' }).click();
  await expect(page.getByText('Welfare payout recorded.')).toBeVisible();
  await expect(row.locator('.status-pill')).toContainText('Paid');
  await expect(row.getByRole('button', { name: 'Pay claim' })).toHaveCount(0);
  expect(consoleErrors).toEqual([]);
});
