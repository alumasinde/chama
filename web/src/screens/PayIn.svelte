<script lang="ts">
  import { onDestroy } from 'svelte';
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import type { StkResult, Transaction } from '../lib/types';

  let { onclose }: { onclose: () => void } = $props();

  const group = activeGroup();
  let step = $state<'details' | 'pin' | 'pending' | 'receipt' | 'failed'>('details');
  let amount = $state(group?.contribution_amount ?? '1000.00');
  let purpose = $state('contribution');
  let phone = $state(session.user?.phone_number ?? '');
  let pin = $state('');
  let busy = $state(false);
  let error = $state('');
  let stk = $state<StkResult | null>(null);
  let receipt = $state<Transaction | null>(null);
  let startedAt = 0;
  let timer: ReturnType<typeof setInterval> | null = null;
  let elapsed = $state(0);

  const purposes: [string, string][] = [
    ['contribution', 'Contribution'],
    ['fine', 'Fine'],
    ['loan_repayment', 'Loan repayment'],
    ['welfare_contribution', 'Welfare'],
  ];

  function stop() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  onDestroy(stop);

  function sameAmount(left: string, right: string): boolean {
    return Number(left).toFixed(2) === Number(right).toFixed(2);
  }

  function fail(err: unknown, fallback: string) {
    error = err instanceof ApiFailure ? err.message : fallback;
  }

  async function send() {
    if (!group || !session.access) return;
    error = '';
    busy = true;
    try {
      const verified = await api<{ step_up_token: string }>('/auth/pin/verify', {
        method: 'POST',
        auth: session.access,
        body: { pin },
        retry: false,
      });
      const result = await api<StkResult>(`/groups/${group.id}/payments/stk`, {
        method: 'POST',
        auth: session.access,
        headers: {
          'X-Step-Up-Token': verified.step_up_token,
          'Idempotency-Key': crypto.randomUUID(),
        },
        body: { amount, purpose, ...(phone.trim() ? { phone_number: phone.trim() } : {}) },
        retry: false,
      });
      stk = result;
      pin = '';
      startedAt = Date.now();
      step = 'pending';
      void poll();
    } catch (err) {
      fail(err, 'Could not start the M-Pesa request.');
    } finally {
      busy = false;
    }
  }

  async function check() {
    if (!group || !session.access) return;
    try {
      const result = await api<{ data: Transaction[] }>(
        `/groups/${group.id}/transactions?limit=10`,
        { auth: session.access },
      );
      const match = result.data.find(
        (row) =>
          row.type === purpose &&
          sameAmount(row.amount, amount) &&
          new Date(row.created_at).getTime() >= startedAt - 60_000,
      );
      if (match?.status === 'completed') {
        receipt = match;
        step = 'receipt';
        stop();
      } else if (match?.status === 'failed') {
        stop();
        step = 'failed';
        error = 'M-Pesa declined the request. Nothing was recorded.';
      } else if (Date.now() - startedAt > 120_000) {
        stop();
      }
    } catch {
      // An interrupted poll is retried; the request itself is already recorded.
    }
  }

  async function poll() {
    stop();
    await check();
    if (step !== 'pending') return;
    timer = setInterval(() => {
      elapsed = Math.round((Date.now() - startedAt) / 1000);
      void check();
    }, 3000);
  }

  const title = $derived(
    step === 'pin'
      ? 'Confirm with your PIN'
      : step === 'pending'
        ? 'Waiting for M-Pesa'
        : step === 'receipt'
          ? 'Payment received'
          : step === 'failed'
            ? 'Payment not completed'
            : 'Pay in',
  );
</script>

<div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) onclose(); }}>
  <div class="modal" role="dialog" aria-modal="true" aria-label="Pay in">
    <div class="section-head" style="margin-bottom: 1rem">
      <h1 style="font-size: 1.25rem">{title}</h1>
      <button class="btn btn-ghost" onclick={onclose} aria-label="Close">✕</button>
    </div>

    {#if error}<p class="error" style="margin-bottom: 0.75rem">{error}</p>{/if}

    {#if step === 'details'}
      <form class="stack" onsubmit={(event) => { event.preventDefault(); step = 'pin'; }} style="display: grid; gap: 1rem">
        <div>
          <label for="pay-amount">Amount (KES)</label>
          <input id="pay-amount" bind:value={amount} inputmode="decimal" placeholder="1500.00" />
          <p class="muted small" style="margin-top: 0.35rem">M-Pesa accepts whole shillings only.</p>
        </div>
        <div class="form-grid">
          <div>
            <label for="pay-purpose">Purpose</label>
            <select id="pay-purpose" bind:value={purpose}>
              {#each purposes as [value, label] (value)}
                <option {value}>{label}</option>
              {/each}
            </select>
          </div>
          <div>
            <label for="pay-phone">Phone (optional)</label>
            <input id="pay-phone" bind:value={phone} inputmode="tel" placeholder={session.user?.phone_number} />
          </div>
        </div>
        <p class="muted small">
          Money moves from your phone to {group?.name ?? 'your chama'}'s own shortcode. This platform only records it.
        </p>
        <div style="display: flex; gap: 0.75rem; justify-content: flex-end">
          <button class="btn btn-secondary" type="button" onclick={onclose}>Cancel</button>
          <button class="btn btn-primary" type="submit" disabled={!amount.trim()}>Continue</button>
        </div>
      </form>
    {:else if step === 'pin'}
      <form class="stack" onsubmit={(event) => { event.preventDefault(); void send(); }} style="display: grid; gap: 1rem">
        <p class="muted small">
          Sending <strong>KES {amount}</strong> as a {purposes.find(([value]) => value === purpose)?.[1]?.toLowerCase() ?? 'contribution'}.
        </p>
        <div>
          <label for="pay-pin">4-digit PIN</label>
          <input id="pay-pin" bind:value={pin} type="password" maxlength="4" inputmode="numeric" autocomplete="current-password" />
        </div>
        <div style="display: flex; gap: 0.75rem; justify-content: flex-end">
          <button class="btn btn-secondary" type="button" onclick={() => { step = 'details'; error = ''; }} disabled={busy}>Back</button>
          <button class="btn btn-primary" type="submit" disabled={busy || pin.length !== 4}>
            {busy ? 'Sending…' : 'Send M-Pesa request'}
          </button>
        </div>
      </form>
    {:else if step === 'pending'}
      <div class="empty" style="padding: 1rem 0">
        <h3>Check your phone</h3>
        <p class="small">
          Approve the M-Pesa prompt for <strong>KES {stk?.amount ?? amount}</strong> on {phone || 'your phone'}.
        </p>
        <p class="muted small" style="margin-top: 0.75rem">
          {elapsed < 5 ? 'Waiting for the prompt…' : `Still waiting · ${elapsed}s`}
        </p>
        <button class="btn btn-secondary" style="margin-top: 1rem" onclick={onclose}>Close and check later</button>
      </div>
    {:else if step === 'receipt' && receipt}
      <div>
        <div class="balance" style="margin-bottom: 1rem">
          <span class="label">Received</span>
          <span class="amount">{group?.currency ?? 'KES'} {receipt.amount}</span>
          <span class="meta">{receipt.member} · {receipt.type.replace('_', ' ')}</span>
        </div>
        <div class="grid-2">
          <div class="stat">
            <span class="muted small">M-Pesa receipt</span>
            <span class="value" style="font-size: 1.1rem">{receipt.reference_code ?? '—'}</span>
          </div>
          <div class="stat">
            <span class="muted small">Completed</span>
            <span class="value" style="font-size: 1.1rem">
              {receipt.completed_at ? new Date(receipt.completed_at).toLocaleString('en-KE') : '—'}
            </span>
          </div>
        </div>
        <p class="muted small" style="margin: 0.75rem 0 1rem">This entry is now part of the chama ledger.</p>
        <div style="display: flex; justify-content: flex-end">
          <button class="btn btn-primary" onclick={onclose}>Done</button>
        </div>
      </div>
    {:else}
      <div class="empty" style="padding: 1rem 0">
        <p class="small">The request was not completed. You can try again.</p>
        <button class="btn btn-primary" style="margin-top: 1rem" onclick={() => { step = 'details'; error = ''; }}>Try again</button>
      </div>
    {/if}
  </div>
</div>
