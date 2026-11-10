import { request, test as setup, type APIRequestContext } from '@playwright/test';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { authPath, type Role, type StoredSession } from './support';

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:8081';
const API_BASE = `${BASE_URL.replace(/\/$/, '')}/api/v1`;
const ADMIN_PHONE = process.env.E2E_ADMIN_PHONE || '0712991122';
const MEMBER_PHONE = process.env.E2E_MEMBER_PHONE || '0712991144';

type AuthResponse = {
  refresh_token: string;
  user: unknown;
};

type VerifyResponse = {
  session?: AuthResponse;
};

function readExisting(role: Role): StoredSession | null {
  try {
    const saved = JSON.parse(readFileSync(authPath(role), 'utf8')) as StoredSession;
    return saved.refresh ? saved : null;
  } catch {
    return null;
  }
}

function save(role: Role, state: StoredSession) {
  mkdirSync(new URL('../.auth/', import.meta.url), { recursive: true });
  writeFileSync(authPath(role), JSON.stringify(state));
}

async function refreshSession(api: APIRequestContext, saved: StoredSession | null): Promise<StoredSession | null> {
  if (!saved?.refresh) return null;
  const response = await api.post(`${API_BASE}/auth/token/refresh`, {
    data: { refresh_token: saved.refresh },
  });
  if (!response.ok()) return null;
  const auth = (await response.json()) as AuthResponse;
  if (!auth.refresh_token) return null;
  return { refresh: auth.refresh_token, user: auth.user };
}

async function login(api: APIRequestContext, phone: string): Promise<StoredSession> {
  const otp = await api.post(`${API_BASE}/auth/otp/request`, {
    data: { phone_number: phone, purpose: 'login' },
  });
  if (!otp.ok()) {
    const detail = await otp.text();
    throw new Error(
      `Could not request an OTP for ${phone}: ${otp.status()} ${detail}. ` +
      'Wait for the development OTP cooldown, or set E2E_ADMIN_PHONE / E2E_MEMBER_PHONE to an active account.',
    );
  }
  const { dev_code: code } = (await otp.json()) as { dev_code?: string };
  if (!code) throw new Error('The development server did not return a dev_code.');

  const verified = await api.post(`${API_BASE}/auth/otp/verify`, {
    data: { phone_number: phone, code, purpose: 'login' },
  });
  if (!verified.ok()) {
    const detail = await verified.text();
    throw new Error(`Could not verify the OTP for ${phone}: ${verified.status()} ${detail}`);
  }
  const result = (await verified.json()) as VerifyResponse;
  if (!result.session?.refresh_token) {
    throw new Error(`${phone} is not registered in this demo database.`);
  }
  return { refresh: result.session.refresh_token, user: result.session.user };
}

async function prepare(api: APIRequestContext, role: Role, phone: string) {
  const saved = readExisting(role);
  const refreshed = await refreshSession(api, saved);
  if (refreshed) {
    save(role, refreshed);
    return;
  }
  save(role, await login(api, phone));
}

setup('prepare reusable admin and member sessions', async () => {
  const api = await request.newContext({ baseURL: API_BASE });
  try {
    await prepare(api, 'admin', ADMIN_PHONE);
    await prepare(api, 'member', MEMBER_PHONE);
  } finally {
    await api.dispose();
  }
});
