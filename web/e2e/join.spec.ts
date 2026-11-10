import { expect, test } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import { authPath, openAs, openInviteAs, persistSession, type StoredSession } from './support';

const inviteCode = process.env.E2E_INVITE_CODE || '';

test('public invite landing explains the chama and asks the visitor to sign in', async ({ page }) => {
  test.skip(!inviteCode, 'Set E2E_INVITE_CODE to a seeded invite code.');

  const consoleErrors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });

  await page.goto(`/join/${inviteCode}`);
  await expect(page.locator('.auth-card h1')).toContainText('Join');
  await expect(page.getByRole('button', { name: 'Sign in to request to join' })).toBeVisible();
  await expect(page.getByText('Active members')).toBeVisible();
  expect(consoleErrors).toEqual([]);
});

test('a signed-in visitor returns to the pending invite through the login URL', async ({ page }) => {
  test.skip(!inviteCode, 'Set E2E_INVITE_CODE to a seeded invite code.');

  await openAs(page, 'admin');
  await page.evaluate((code) => sessionStorage.setItem('chama.pendingInvite.v1', code), inviteCode);
  await page.goto('/login');
  await expect(page).toHaveURL(new RegExp(`/join/${inviteCode}$`));
  await expect(page.getByRole('button', { name: 'Request to join', exact: true })).toBeVisible();
  await persistSession(page, 'admin');

  await page.evaluate(() => sessionStorage.removeItem('chama.pendingInvite.v1'));
  await page.goto('/login');
  await expect(page).toHaveURL(/\/app(?:#|$)/);
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toBeVisible();
  await persistSession(page, 'admin');
});

test('signed-in member can request to join from the invite landing', async ({ browser, request }) => {
  const saved = JSON.parse(readFileSync(authPath('admin'), 'utf8')) as StoredSession;
  const refreshed = await request.post('/api/v1/auth/token/refresh', {
    data: { refresh_token: saved.refresh },
  });
  expect(refreshed.ok()).toBeTruthy();
  const admin = (await refreshed.json()) as {
    access_token: string;
    refresh_token: string;
    user: unknown;
  };
  writeFileSync(authPath('admin'), JSON.stringify({ refresh: admin.refresh_token, user: admin.user }));

  const created = await request.post('/api/v1/groups', {
    headers: { Authorization: `Bearer ${admin.access_token}` },
    data: {
      name: `Invite flow ${Date.now()}`,
      contribution_amount: '100.00',
      contribution_frequency: 'monthly',
    },
  });
  expect(created.status()).toBe(201);
  const group = (await created.json()) as { name: string; invite_code: string };

  const context = await browser.newContext();
  const page = await context.newPage();
  try {
    await openInviteAs(page, 'member', `/join/${group.invite_code}`);
    await expect(page.getByRole('heading', { level: 1, name: `Join ${group.name}` })).toBeVisible();
    await page.getByRole('button', { name: 'Request to join', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Request sent' })).toBeVisible();
    await expect(page.getByText(`Your request to join ${group.name}`)).toBeVisible();
  } finally {
    await context.close();
  }
});
