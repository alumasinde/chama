import { expect, type Page } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';

export const SESSION_KEY = 'chama.session.v1';
export type Role = 'admin' | 'member';

export type StoredSession = {
  refresh: string;
  user: unknown;
};

export function authPath(role: Role) {
  return new URL(`../.auth/${role}.json`, import.meta.url);
}

export function readSession(role: Role): StoredSession {
  return JSON.parse(readFileSync(authPath(role), 'utf8')) as StoredSession;
}

export async function persistSession(page: Page, role: Role) {
  const current = await page.evaluate((key) => window.sessionStorage.getItem(key), SESSION_KEY);
  if (current) writeFileSync(authPath(role), current);
}

async function seedSession(page: Page, role: Role) {
  const saved = readSession(role);
  // The app deliberately keeps tokens in sessionStorage, which Playwright's
  // storageState does not capture. Seed the same key before the app boots, but
  // never overwrite a token the app has already rotated during a later load.
  await page.addInitScript(({ key, value }: { key: string; value: string }) => {
    try {
      if (!window.sessionStorage.getItem(key)) window.sessionStorage.setItem(key, value);
    } catch {
      // The initial about:blank document has no storage; the app page will.
    }
  }, { key: SESSION_KEY, value: JSON.stringify(saved) });
}

export async function openAs(page: Page, role: Role) {
  await seedSession(page, role);
  await page.goto('/app');
  await expect(page).toHaveURL(/\/app(?:#|$)/);
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toBeVisible();

  // The app refreshes on boot and rotates the refresh token. Persist the new
  // one so the next test or run does not need another OTP.
  await persistSession(page, role);
}

// Navigate straight to an invite so a second page load cannot re-seed the
// pre-rotation refresh token from the init script.
export async function openInviteAs(page: Page, role: Role, path: string) {
  await seedSession(page, role);
  await page.goto(path);
  await expect(page.getByRole('button', { name: 'Request to join', exact: true })).toBeVisible();
  await persistSession(page, role);
}

export async function selectGroup(page: Page, name = 'Umoja Women') {
  const select = page.getByLabel('Active chama');
  await expect(select).toBeVisible();
  await select.selectOption({ label: name });
}
