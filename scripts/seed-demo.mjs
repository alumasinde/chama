#!/usr/bin/env node
// Seeds the demo chama and exercises one welfare claim and one rotation payout.
// Usage:
//   DEMO_PHONE=0712991122 DEMO_PIN=**** node scripts/seed-demo.mjs
//   DEMO_ACCESS_TOKEN=... DEMO_PIN=**** node scripts/seed-demo.mjs
// The script never prints access, refresh or step-up tokens.

const API = (process.env.DEMO_API || 'http://localhost:8081/api/v1').replace(/\/$/, '');
const PHONE = process.env.DEMO_PHONE || '';
const PIN = process.env.DEMO_PIN || '';
const GROUP_ID = process.env.DEMO_GROUP_ID || '';
const GROUP_NAME = process.env.DEMO_GROUP_NAME || 'Umoja Women';
const PERIOD = new Date().toISOString().slice(0, 7);
const CLAIM_REASON = 'Demo seed: household emergency';
const CYCLE_NAME = 'Demo 2026 rotation';

async function request(path, { method = 'GET', token, body, headers = {} } = {}) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let payload = null;
  try { payload = text ? JSON.parse(text) : null; } catch { /* keep text */ }
  if (!response.ok) {
    const message = payload?.error?.message || text || response.statusText;
    throw new Error(`${method} ${path} -> ${response.status}: ${message}`);
  }
  return payload;
}

async function login() {
  if (process.env.DEMO_ACCESS_TOKEN) {
    const groups = await request('/groups', { token: process.env.DEMO_ACCESS_TOKEN });
    return { token: process.env.DEMO_ACCESS_TOKEN, groups };
  }
  if (!PHONE) throw new Error('Set DEMO_PHONE or DEMO_ACCESS_TOKEN.');
  const otp = await request('/auth/otp/request', {
    method: 'POST', body: { phone_number: PHONE, purpose: 'login' },
  });
  if (!otp?.dev_code) throw new Error('Development OTP was not returned by this server.');
  const auth = await request('/auth/otp/verify', {
    method: 'POST', body: { phone_number: PHONE, code: otp.dev_code, purpose: 'login' },
  });
  return { token: auth.session.access_token, groups: await request('/groups', { token: auth.session.access_token }) };
}

async function stepUp(token) {
  if (!PIN) throw new Error('Set DEMO_PIN to authorise contributions and payouts.');
  const result = await request('/auth/pin/verify', { method: 'POST', token, body: { pin: PIN } });
  if (!result?.step_up_token) throw new Error('PIN verification did not return a step-up token.');
  return result.step_up_token;
}

async function main() {
  const session = await login();
  const token = session.token;
  const groups = session.groups?.data || session.groups || [];
  const group = GROUP_ID ? groups.find((row) => row.id === GROUP_ID) : groups.find((row) => row.name === GROUP_NAME);
  if (!group) throw new Error(`Group not found: ${GROUP_ID || GROUP_NAME}`);

  const [members, fundBefore, contributionsBefore] = await Promise.all([
    request(`/groups/${group.id}/members`, { token }),
    request(`/groups/${group.id}/welfare`, { token }),
    request(`/groups/${group.id}/welfare/contributions?limit=100`, { token }),
  ]);
  const me = members.data.find((row) => row.role === 'admin') || members.data[0];
  const other = members.data.find((row) => row.status === 'active' && row.user_id !== me.user_id);

  let fund = fundBefore;
  if (!fund.configured) {
    fund = await request(`/groups/${group.id}/welfare`, {
      method: 'PUT', token,
      body: { name: 'Umoja Welfare', monthly_amount: '500.00', is_active: true },
    });
  }

  const seededContributions = [];
  for (const member of [me, other].filter(Boolean)) {
    const existing = contributionsBefore.data.find((row) => row.user_id === member.user_id && row.period_label === PERIOD);
    if (existing) {
      seededContributions.push({ member: member.display_name, amount: existing.amount, reused: true });
      continue;
    }
    const step = await stepUp(token);
    const contribution = await request(`/groups/${group.id}/welfare/contributions`, {
      method: 'POST', token,
      headers: { 'X-Step-Up-Token': step, 'Idempotency-Key': `demo-welfare-${member.user_id}-${PERIOD}` },
      body: {
        user_id: member.user_id, amount: member.user_id === me.user_id ? '1500.00' : '500.00',
        period_label: PERIOD, channel: 'cash', reference: `DEMO-WELFARE-${PERIOD}-${member.user_id.slice(0, 8)}`,
      },
    });
    seededContributions.push({ member: member.display_name, amount: contribution.amount, reused: false });
  }

  const claims = await request(`/groups/${group.id}/welfare/claims?limit=100`, { token });
  let claim = claims.data.find((row) => row.reason === CLAIM_REASON && row.status !== 'rejected');
  if (!claim) {
    claim = await request(`/groups/${group.id}/welfare/claims`, {
      method: 'POST', token, body: { amount: '500.00', reason: CLAIM_REASON },
    });
  }
  if (claim.status === 'pending') {
    claim = await request(`/groups/${group.id}/welfare/claims/${claim.id}/decision`, {
      method: 'POST', token, body: { decision: 'approved', comment: 'Approved in the demo seed.' },
    });
  }
  if (claim.status === 'approved') {
    const step = await stepUp(token);
    const paid = await request(`/groups/${group.id}/welfare/claims/${claim.id}/payout`, {
      method: 'POST', token,
      headers: { 'X-Step-Up-Token': step, 'Idempotency-Key': `demo-claim-payout-${claim.id}` },
      body: { channel: 'mpesa_manual', reference: 'DEMO-CLAIM-PAYOUT' },
    });
    claim = paid.claim;
  }

  const cycles = await request(`/groups/${group.id}/rotation/cycles?limit=50`, { token });
  let cycle = cycles.data.find((row) => row.name === CYCLE_NAME);
  if (!cycle) {
    cycle = await request(`/groups/${group.id}/rotation/cycles`, {
      method: 'POST', token,
      body: {
        name: CYCLE_NAME, ordering_mode: 'random', contribution_amount: '1500.00',
        starts_on: new Date().toISOString().slice(0, 10),
      },
    });
  }
  if (cycle.status === 'draft') {
    cycle = await request(`/groups/${group.id}/rotation/cycles/${cycle.id}/start`, { method: 'POST', token });
  }
  if (cycle.status === 'active' && cycle.paid_count === 0) {
    const fresh = await request(`/groups/${group.id}/rotation/cycles/${cycle.id}`, { token });
    const slot = fresh.slots.find((row) => !row.paid);
    if (slot) {
      const step = await stepUp(token);
      await request(`/groups/${group.id}/rotation/cycles/${cycle.id}/payouts`, {
        method: 'POST', token,
        headers: { 'X-Step-Up-Token': step, 'Idempotency-Key': `demo-rotation-payout-${cycle.id}` },
        body: { slot_id: slot.id, channel: 'mpesa_manual', reference: 'DEMO-ROTATION-PAYOUT' },
      });
    }
  }

  const [fundAfter, claimAfter, cycleAfter] = await Promise.all([
    request(`/groups/${group.id}/welfare`, { token }),
    request(`/groups/${group.id}/welfare/claims?limit=100`, { token }),
    request(`/groups/${group.id}/rotation/cycles/${cycle.id}`, { token }),
  ]);
  const finalClaim = claimAfter.data.find((row) => row.id === claim.id) || claim;
  console.log(JSON.stringify({
    group: group.name,
    fund: { configured: fundAfter.configured, balance: fundAfter.balance, contributed: fundAfter.contributed_total },
    contributions: seededContributions,
    claim: { id: finalClaim.id, status: finalClaim.status, amount: finalClaim.amount, member: finalClaim.member },
    rotation: { id: cycleAfter.id, name: cycleAfter.name, status: cycleAfter.status, paid_count: cycleAfter.paid_count, slots: cycleAfter.slot_count },
  }, null, 2));
}

main().catch((error) => {
  console.error(`seed failed: ${error.message}`);
  process.exit(1);
});
