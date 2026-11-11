<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, canManagePayments, session } from '../lib/session.svelte';
  import { money } from '../lib/format';
  import type { ManualContribution, Member } from '../lib/types';

  let { onclose, onrecorded }: { onclose: () => void; onrecorded: () => void } = $props();

  const group = activeGroup();
  let members = $state<Member[]>([]);
  let memberId = $state('');
  let amount = $state(group?.contribution_amount ?? '');
  let reference = $state('');
  let narration = $state('');
  let pin = $state('');
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let fields = $state<Record<string, string>>({});
  let step = $state<'details' | 'pin' | 'receipt'>('details');
  let receipt = $state<ManualContribution | null>(null);

  const memberName = $derived(members.find((row) => row.user_id === memberId)?.display_name ?? '');

  $effect(() => {
    void loadMembers();
  });

  async function loadMembers() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    try {
      const result = await api<{ data: Member[] }>(`/groups/${session.activeGroupId}/members`, {
        auth: session.access,
      });
      members = result.data.filter((row) => row.status === 'active');
      memberId = members[0]?.user_id ?? '';
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load the chama members.';
    } finally {
      loading = false;
    }
  }

  function fail(err: unknown, fallback: string) {
    error = err instanceof ApiFailure ? err.message : fallback;
    fields = err instanceof ApiFailure ? (err.fields ?? {}) : {};
    if (Object.keys(fields).length > 0) step = 'details';
  }

  async function confirm() {
    if (!group || !session.access) return;
    error = '';
    fields = {};
    busy = true;
    try {
      const verified = await api<{ step_up_token: string }>('/auth/pin/verify', {
        method: 'POST',
        auth: session.access,
        body: { pin },
        retry: false,
      });
      const saved = await api<ManualContribution>(`/groups/${group.id}/payments/manual`, {
        method: 'POST',
        auth: session.access,
        headers: { 'X-Step-Up-Token': verified.step_up_token },
        body: { member_id: memberId, amount, reference, narration },
        retry: false,
      });
      receipt = saved;
      step = 'receipt';
      pin = '';
      onrecorded();
    } catch (err) {
      fail(err, 'Could not record that payment.');
    } finally {
      busy = false;
    }
  }

  const title = $derived(
    step === 'pin' ? 'Confirm with your PIN' : step === 'receipt' ? 'Payment recorded' : 'Record a payment',
  );
</script>

<div
  class="modal-backdrop"
  role="presentation"
  onclick={(event) => {
    if (event.target === event.currentTarget && !busy) onclose();
  }}
>
  <div class="modal" role="dialog" aria-modal="true" aria-label="Record a payment">
    <div class="section-head" style="margin-bottom: 1rem">
      <h1 style="font-size: 1.25rem">{title}</h1>
      <button class="btn btn-ghost" onclick={onclose} aria-label="Close" disabled={busy}>✕</button>
    </div>

    {#if !canManagePayments()}
      <p class="notice">Only admins and treasurers can record a payment.</p>
    {:else if step === 'receipt' && receipt}
      <div>
        <div class="balance" style="margin-bottom: 1rem">
          <span class="label">Recorded</span>
          <span class="amount">{group?.currency ?? 'KES'} {receipt.amount}</span>
          <span class="meta">{memberName} · contribution</span>
        </div>
        <div class="grid-2">
          <div class="stat">
            <span class="muted small">M-Pesa receipt</span>
            <span class="value mono" style="font-size: 1.1rem">{receipt.reference}</span>
          </div>
          <div class="stat">
            <span class="muted small">Recorded</span>
            <span class="value" style="font-size: 1.1rem">{new Date(receipt.recorded_at).toLocaleString('en-KE')}</span>
          </div>
        </div>
        <p class="muted small" style="margin: 0.75rem 0 1rem">
          This entry is now part of the chama ledger and cannot be recorded twice.
        </p>
        <div style="display: flex; justify-content: flex-end">
          <button class="btn btn-primary" onclick={onclose}>Done</button>
        </div>
      </div>
    {:else}
      {#if error}<p class="error" style="margin-bottom: 0.75rem">{error}</p>{/if}

      <form
        class="stack"
        onsubmit={(event) => {
          event.preventDefault();
          if (step === 'details') {
            error = '';
            pin = '';
            step = 'pin';
          } else {
            void confirm();
          }
        }}
        style="display: grid; gap: 1rem"
      >
        {#if step === 'details'}
          {#if loading}
            <div class="empty compact"><p>Loading members…</p></div>
          {:else if members.length === 0}
            <p class="notice">No active members yet. Approve a member before recording their payment.</p>
          {:else}
            <div>
              <label for="manual-member">Member who paid</label>
              <select id="manual-member" bind:value={memberId}>
                {#each members as member (member.user_id)}
                  <option value={member.user_id}>{member.display_name}</option>
                {/each}
              </select>
              {#if fields.member_id}<p class="small error" style="margin-top: 0.4rem">{fields.member_id}</p>{/if}
            </div>
            <div class="form-grid">
              <div>
                <label for="manual-amount">Amount (KES)</label>
                <input id="manual-amount" bind:value={amount} inputmode="decimal" placeholder="1500.00" />
                {#if fields.amount}<p class="small error" style="margin-top: 0.4rem">{fields.amount}</p>{/if}
              </div>
              <div>
                <label for="manual-reference">M-Pesa code</label>
                <input
                  id="manual-reference"
                  bind:value={reference}
                  autocomplete="off"
                  spellcheck="false"
                  placeholder="SLK7XQ2P9D"
                />
                {#if fields.reference}<p class="small error" style="margin-top: 0.4rem">{fields.reference}</p>{/if}
              </div>
            </div>
            <div>
              <label for="manual-note">Note (optional)</label>
              <input id="manual-note" bind:value={narration} placeholder="Cash at the meeting, handset transfer…" />
              {#if fields.narration}<p class="small error" style="margin-top: 0.4rem">{fields.narration}</p>{/if}
            </div>
            <p class="muted small">
              For cash, a bank deposit or an M-Pesa payment the treasurer already received. The code must not
              already be in this chama's ledger.
            </p>
          {/if}

          <div style="display: flex; gap: 0.75rem; justify-content: flex-end">
            <button class="btn btn-secondary" type="button" onclick={onclose}>Cancel</button>
            <button
              class="btn btn-primary"
              type="submit"
              disabled={loading || members.length === 0 || !amount.trim() || !reference.trim()}
            >
              Continue
            </button>
          </div>
        {:else}
          <p class="muted small">
            Recording <strong>{money(amount, group?.currency)}</strong> for <strong>{memberName}</strong> with M-Pesa code
            <strong class="mono">{reference}</strong>.
          </p>
          <div>
            <label for="manual-pin">4-digit PIN</label>
            <input
              id="manual-pin"
              bind:value={pin}
              type="password"
              maxlength="4"
              inputmode="numeric"
              autocomplete="current-password"
            />
          </div>
          <div style="display: flex; gap: 0.75rem; justify-content: flex-end">
            <button class="btn btn-secondary" type="button" onclick={() => { step = 'details'; error = ''; }} disabled={busy}>
              Back
            </button>
            <button class="btn btn-primary" type="submit" disabled={busy || pin.length !== 4}>
              {busy ? 'Recording…' : 'Save payment'}
            </button>
          </div>
        {/if}
      </form>
    {/if}
  </div>
</div>
