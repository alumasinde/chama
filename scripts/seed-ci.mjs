#!/usr/bin/env node
// Creates the fixed CI demo accounts, chama and browser sessions.
// This script never prints access or refresh tokens.
//
//   SEED_OUTPUT=/tmp/chama-seed.json AUTH_DIR=web/.auth node scripts/seed-ci.mjs

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const API = (process.env.CI_API || process.env.DEMO_API || 'http://localhost:8081/api/v1').replace(/\/$/, '');
const AUTH_DIR = resolve(process.env.AUTH_DIR || 'web/.auth');
const OUTPUT = process.env.SEED_OUTPUT || '';
const PIN = process.env.E2E_PIN || '4826';
const PASSWORD = process.env.E2E_PASSWORD || 'ChamaStrong2026';

const ADMIN = {
  phone: process.env.E2E_ADMIN_PHONE || '0712991122',
  first_name: 'Wanjiku',
  last_name: 'Kamau',
};
const MEMBER = {
  phone: process.env.E2E_MEMBER_PHONE || '0712991144',
  first_name: 'Njeri',
  last_name: 'Mwangi',
};

async function request(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let payload = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch {
    // Keep the raw text in the error below.
  }
  if (!response.ok) {
    const error = new Error(`${method} ${path} -> ${response.status}: ${payload?.error?.message || text || response.statusText}`);
    error.status = response.status;
    error.code = payload?.error?.code;
    throw error;
  }
  return payload;
}

async function sessionFor(account) {
  const otp = await request('/auth/otp/request', {
    method: 'POST',
    body: { phone_number: account.phone, purpose: 'login' },
  });
  if (!otp?.dev_code) throw new Error('The development server did not return a dev_code.');

  const verified = await request('/auth/otp/verify', {
    method: 'POST',
    body: { phone_number: account.phone, code: otp.dev_code, purpose: 'login' },
  });
  if (verified?.session) return verified.session;
  if (!verified?.registration_token) {
    throw new Error(`${account.phone} is neither registered nor eligible to register.`);
  }
  return request('/auth/register', {
    method: 'POST',
    token: verified.registration_token,
    body: {
      first_name: account.first_name,
      last_name: account.last_name,
      pin: PIN,
      password: PASSWORD,
    },
  });
}

function writeSession(role, session) {
  mkdirSync(AUTH_DIR, { recursive: true });
  writeFileSync(join(AUTH_DIR, `${role}.json`), JSON.stringify({
    refresh: session.refresh_token,
    user: session.user,
  }));
}

async function main() {
  const admin = await sessionFor(ADMIN);
  const member = await sessionFor(MEMBER);

  const groups = await request('/groups', { token: admin.access_token });
  let group = groups.data.find((row) => row.name === 'Umoja Women');
  if (!group) {
    group = await request('/groups', {
      method: 'POST',
      token: admin.access_token,
      body: {
        name: 'Umoja Women',
        description: 'Monthly savings',
        contribution_amount: '1500.00',
        contribution_frequency: 'monthly',
        contribution_day: 5,
        late_grace_days: 3,
      },
    });
  }

  try {
    await request('/groups/join', {
      method: 'POST',
      token: member.access_token,
      body: { invite_code: group.invite_code },
    });
  } catch (error) {
    if (error.status !== 409) throw error;
  }

  const members = await request(`/groups/${group.id}/members`, { token: admin.access_token });
  const memberRow = members.data.find((row) => row.user_id === member.user.id);
  if (memberRow && memberRow.status !== 'active') {
    await request(`/groups/${group.id}/members/${memberRow.user_id}`, {
      method: 'PATCH',
      token: admin.access_token,
      body: { status: 'active' },
    });
  }

  writeSession('admin', admin);
  writeSession('member', member);

  const output = {
    admin_access_token: admin.access_token,
    group_id: group.id,
    invite_code: group.invite_code,
    member_id: member.user.id,
  };
  if (OUTPUT) {
    mkdirSync(dirname(OUTPUT), { recursive: true });
    writeFileSync(OUTPUT, JSON.stringify(output));
  }
  console.log(JSON.stringify({
    group: group.name,
    invite_code: group.invite_code,
    admin: admin.user.display_name,
    member: member.user.display_name,
  }, null, 2));
}

main().catch((error) => {
  console.error(`seed-ci failed: ${error.message}`);
  process.exit(1);
});
