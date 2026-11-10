<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, number, dateShort, titleCase, tone, initials } from '../lib/format';
  import type { Fine } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';
  import PinModal from '../components/PinModal.svelte';

  type FineRule = { fine_type: string; calculation_method: string; amount_or_rate: string; grace_days: number; updated_at: string };
  const group = $derived(activeGroup());
  const manager = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  const canWaive = $derived(['admin', 'treasurer'].includes(group?.role ?? ''));
  const canExport = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  let fines = $state<Fine[]>([]);
  let rules = $state<FineRule[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let tab = $state<'fines' | 'rules'>('fines');
  let filter = $state('all');
  let waiveTarget = $state<Fine | null>(null);
  let waiveReason = $state('');
  let payTarget = $state<Fine | null>(null);
  let payOpen = $state(false);
  let channel = $state('mpesa_manual');
  let reference = $state('');
  let pinOpen = $state(false);

  const filtered = $derived(fines.filter((fine) => filter === 'all' || fine.status === filter));
  const unpaid = $derived(fines.filter((fine) => fine.status === 'unpaid').reduce((total, fine) => total + number(fine.amount), 0));
  const waived = $derived(fines.filter((fine) => fine.status === 'waived').length);
  const paid = $derived(fines.filter((fine) => fine.status === 'paid').length);

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const [fineResult, ruleResult] = await Promise.all([
        api<{ data: Fine[] }>(`/groups/${session.activeGroupId}/fines?limit=100`, { auth: session.access }),
        api<{ data: FineRule[] }>(`/groups/${session.activeGroupId}/fines/rules`, { auth: session.access }),
      ]);
      fines = fineResult.data;
      rules = ruleResult.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load fines.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  async function evaluate() {
    if (!session.activeGroupId || !session.access) return;
    error = '';
    try {
      const result = await api<{ fines_created: number }>(`/groups/${session.activeGroupId}/fines/evaluate`, { method: 'POST', auth: session.access });
      notice = `${result.fines_created} fine${result.fines_created === 1 ? '' : 's'} created for the last period.`;
      await load();
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not run fine evaluation.';
    }
  }

  async function waive() {
    if (!session.activeGroupId || !session.access || !waiveTarget) return;
    error = '';
    try {
      await api(`/groups/${session.activeGroupId}/fines/${waiveTarget.id}/waive`, {
        method: 'POST', auth: session.access, body: { reason: waiveReason },
      });
      waiveTarget = null;
      waiveReason = '';
      notice = 'Fine waived.';
      await load();
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not waive that fine.';
    }
  }

  function startPay(fine: Fine) {
    payTarget = fine;
    payOpen = true;
    pinOpen = false;
    channel = 'mpesa_manual';
    reference = '';
  }

  function confirmPay() {
    payOpen = false;
    pinOpen = true;
  }

  async function pay(token: string) {
    if (!session.activeGroupId || !session.access || !payTarget) return;
    await api(`/groups/${session.activeGroupId}/fines/${payTarget.id}/pay`, {
      method: 'POST', auth: session.access,
      headers: { 'X-Step-Up-Token': token, 'Idempotency-Key': crypto.randomUUID() },
      body: { amount: payTarget.amount, channel, ...(reference.trim() ? { reference: reference.trim() } : {}) },
    });
    pinOpen = false;
    payOpen = false;
    notice = `${payTarget.member}'s fine is paid.`;
    payTarget = null;
    await load();
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Accountability</p><h1>Fines</h1><p>Group rules, assessed fines and the money collected against them.</p></div>
  <div class="page-actions">{#if canExport}<ExportButtons reportCode="fines" />{/if}{#if manager}<button class="btn btn-secondary" type="button" onclick={() => void evaluate()}><Icon name="refresh" size={16} /> Run evaluation</button>{/if}</div>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

<div class="summary-row">
  <div><span>Unpaid</span><strong class="text-danger">{money(unpaid, group?.currency)}</strong></div>
  <div><span>Paid fines</span><strong>{paid}</strong></div>
  <div><span>Waived</span><strong>{waived}</strong></div>
  <div><span>Total assessed</span><strong>{fines.length}</strong></div>
</div>

<div class="tab-bar">
  <button class="tab" class:active={tab === 'fines'} type="button" onclick={() => (tab = 'fines')}>Fines</button>
  <button class="tab" class:active={tab === 'rules'} type="button" onclick={() => (tab = 'rules')}>Rules</button>
</div>

{#if tab === 'fines'}
  <section class="card table-card">
    <div class="card-head"><div><h2>Assessed fines</h2><p>Payments post directly to the ledger.</p></div><div class="segmented"><button class:active={filter === 'all'} type="button" onclick={() => (filter = 'all')}>All</button><button class:active={filter === 'unpaid'} type="button" onclick={() => (filter = 'unpaid')}>Unpaid</button><button class:active={filter === 'paid'} type="button" onclick={() => (filter = 'paid')}>Paid</button></div></div>
    {#if loading}
      <div class="skeleton-rows">{[1,2,3,4].map(() => '<div class="skeleton"></div>')}</div>
    {:else if filtered.length === 0}
      <div class="empty"><span class="empty-icon"><Icon name="fines" size={24} /></span><h3>No fines here</h3><p>Fines appear after an evaluation or a custom charge.</p></div>
    {:else}
      <div class="table-wrap"><table><thead><tr><th>Member</th><th>Reason</th><th>Period</th><th>Amount</th><th>Status</th><th>Assessed</th>{#if canWaive}<th></th>{/if}</tr></thead><tbody>
        {#each filtered as fine (fine.id)}
          <tr>
            <td><span class="person"><span class="avatar avatar-sm">{initials(fine.member)}</span>{fine.member}</span></td>
            <td><strong>{titleCase(fine.fine_type)}</strong><small class="muted">{fine.reason}</small></td>
            <td class="mono">{fine.period_label || '—'}</td>
            <td class="money-cell">{money(fine.amount, group?.currency)}</td>
            <td><span class="status-pill {tone(fine.status)}"><i></i>{titleCase(fine.status)}</span></td>
            <td class="muted small">{dateShort(fine.assessed_on)}</td>
            {#if canWaive}<td class="align-right"><div class="row-actions">{#if fine.status === 'unpaid'}<button class="btn btn-small btn-secondary" type="button" onclick={() => startPay(fine)}>Pay</button><button class="btn btn-small btn-ghost" type="button" onclick={() => { waiveTarget = fine; waiveReason = ''; }}>Waive</button>{/if}</div></td>{/if}
          </tr>
        {/each}
      </tbody></table></div>
    {/if}
  </section>
{:else}
  <section class="card table-card">
    <div class="card-head"><div><h2>Fine rules</h2><p>Rules are applied to the previous contribution period.</p></div><span class="status-pill purple"><i></i>{rules.length} rules</span></div>
    {#if rules.length === 0}
      <div class="empty"><span class="empty-icon"><Icon name="fines" size={24} /></span><h3>No rules configured</h3><p>An admin or treasurer can set group fines through the API.</p></div>
    {:else}
      <div class="rule-grid">{#each rules as rule (rule.fine_type)}<article class="rule-card"><span class="kpi-icon amber"><Icon name="fines" size={18} /></span><strong>{titleCase(rule.fine_type)}</strong><div><span>{rule.calculation_method === 'percentage' ? `${rule.amount_or_rate}%` : money(rule.amount_or_rate, group?.currency)}</span><small>{rule.grace_days} day grace</small></div></article>{/each}</div>
    {/if}
  </section>
{/if}

{#if waiveTarget}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) waiveTarget = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Waive fine">
      <div class="modal-head"><div><h2>Waive fine</h2><p>{waiveTarget.member} · {money(waiveTarget.amount, group?.currency)}</p></div><button class="icon-btn" type="button" onclick={() => (waiveTarget = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void waive(); }}>
        <div><label for="f-waive">Reason for waiving</label><textarea id="f-waive" bind:value={waiveReason} rows="3" maxlength="200" placeholder="This is recorded in the audit trail"></textarea></div>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (waiveTarget = null)}>Cancel</button><button class="btn btn-danger" type="submit" disabled={!waiveReason.trim()}>Waive fine</button></div>
      </form>
    </div>
  </div>
{/if}

{#if payTarget && payOpen}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) { payOpen = false; payTarget = null; } }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Pay fine">
      <div class="modal-head"><div><h2>Pay fine</h2><p>{payTarget.member} · {money(payTarget.amount, group?.currency)}</p></div><button class="icon-btn" type="button" onclick={() => (payTarget = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); confirmPay(); }}>
        <div><label for="f-channel">Channel</label><select id="f-channel" bind:value={channel}><option value="mpesa_manual">M-Pesa manual</option><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="other">Other</option></select></div>
        <div><label for="f-ref">Reference (optional)</label><input id="f-ref" bind:value={reference} placeholder="M-Pesa receipt" /></div>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => { payOpen = false; payTarget = null; }}>Cancel</button><button class="btn btn-green" type="submit">Continue</button></div>
      </form>
    </div>
  </div>
{/if}

{#if pinOpen && payTarget}
  <PinModal title="Confirm fine payment" subtitle={`${payTarget.member} · ${money(payTarget.amount, group?.currency)}`} confirmLabel="Record payment" onclose={() => { pinOpen = false; payTarget = null; }} onconfirm={pay} />
{/if}
