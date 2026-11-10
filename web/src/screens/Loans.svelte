<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, number, dateShort, dateTime, titleCase, tone, percent, initials } from '../lib/format';
  import type { Installment, Loan } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';
  import PinModal from '../components/PinModal.svelte';

  const group = $derived(activeGroup());
  const manager = $derived(['admin', 'treasurer'].includes(group?.role ?? ''));
  const canExport = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  let loans = $state<Loan[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let filter = $state('all');
  let detail = $state<Loan | null>(null);
  let schedule = $state<Installment[]>([]);
  let scheduleLoading = $state(false);
  let actionMode = $state<'disburse' | 'repay' | null>(null);
  let channel = $state('mpesa_manual');
  let reference = $state('');
  let repayAmount = $state('');
  let pinOpen = $state(false);
  let pinTitle = $state('');
  let pinSubtitle = $state('');
  let pinAction: ((token: string) => Promise<void>) | null = $state(null);

  const filtered = $derived(loans.filter((loan) => {
    if (filter === 'all') return true;
    if (filter === 'pending') return loan.status === 'pending_guarantors' || loan.status === 'pending_approval';
    if (filter === 'active') return loan.status === 'active' || loan.status === 'defaulted';
    if (filter === 'closed') return loan.status === 'fully_paid' || loan.status === 'rejected' || loan.status === 'written_off';
    return true;
  }));
  const outstanding = $derived(loans.filter((loan) => ['active', 'defaulted'].includes(loan.status)).reduce((total, loan) => total + number(loan.outstanding), 0));
  const pending = $derived(loans.filter((loan) => ['pending_guarantors', 'pending_approval'].includes(loan.status)).length);
  const active = $derived(loans.filter((loan) => ['active', 'defaulted'].includes(loan.status)).length);

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const result = await api<{ data: Loan[] }>(`/groups/${session.activeGroupId}/loans?limit=100`, { auth: session.access });
      loans = result.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load loans.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  async function openLoan(loan: Loan) {
    if (!session.activeGroupId || !session.access) return;
    detail = loan;
    scheduleLoading = true;
    schedule = [];
    try {
      const [full, rows] = await Promise.all([
        api<Loan>(`/groups/${session.activeGroupId}/loans/${loan.id}`, { auth: session.access }),
        api<{ data: Installment[] }>(`/groups/${session.activeGroupId}/loans/${loan.id}/schedule`, { auth: session.access }),
      ]);
      detail = full;
      schedule = rows.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load the loan schedule.';
    } finally {
      scheduleLoading = false;
    }
  }

  async function decide(decision: 'approved' | 'rejected') {
    if (!session.activeGroupId || !session.access || !detail) return;
    error = '';
    try {
      detail = await api<Loan>(`/groups/${session.activeGroupId}/loans/${detail.id}/decision`, {
        method: 'POST', auth: session.access, body: { decision },
      });
      notice = `Loan ${decision}.`;
      await load();
      await openLoan(detail);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not record that decision.';
    }
  }

  function openAction(mode: 'disburse' | 'repay') {
    actionMode = mode;
    channel = 'mpesa_manual';
    reference = '';
    repayAmount = detail ? detail.outstanding : '';
  }

  function submitAction() {
    if (!session.activeGroupId || !session.access || !detail || !actionMode) return;
    pinTitle = actionMode === 'disburse' ? 'Record loan disbursement' : 'Record loan repayment';
    pinSubtitle = actionMode === 'disburse'
      ? `${money(detail.principal, group?.currency)} leaves the chama ledger for ${detail.borrower}.`
      : `${money(repayAmount, group?.currency)} will be applied to ${detail.borrower}'s loan.`;
    const mode = actionMode;
    pinAction = async (token) => {
      const path = mode === 'disburse' ? 'disburse' : 'repayments';
      await api(`/groups/${session.activeGroupId}/loans/${detail?.id}/${path}`, {
        method: 'POST', auth: session.access,
        headers: { 'X-Step-Up-Token': token, 'Idempotency-Key': crypto.randomUUID() },
        body: {
          channel,
          ...(reference.trim() ? { reference: reference.trim() } : {}),
          ...(mode === 'repay' ? { amount: repayAmount } : {}),
        },
      });
      pinOpen = false;
      actionMode = null;
      notice = mode === 'disburse' ? 'Disbursement recorded.' : 'Repayment recorded.';
      const id = detail?.id;
      await load();
      if (id) await openLoan({ ...(detail as Loan), id });
    };
    pinOpen = true;
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Credit</p><h1>Loans</h1><p>The loan book, repayment schedules and committee decisions.</p></div>
  <div class="page-actions">{#if canExport}<ExportButtons reportCode="loan_book" />{/if}<button class="btn btn-secondary" type="button" onclick={() => void load()}><Icon name="refresh" size={16} /> Refresh</button></div>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

<div class="summary-row">
  <div><span>Outstanding</span><strong class="money-cell">{money(outstanding, group?.currency)}</strong></div>
  <div><span>Active loans</span><strong>{active}</strong></div>
  <div><span>Awaiting a decision</span><strong>{pending}</strong></div>
  <div><span>Total requests</span><strong>{loans.length}</strong></div>
</div>

<div class="tab-bar">
  {#each [['all', 'All'], ['pending', 'Pending'], ['active', 'Active'], ['closed', 'Closed']] as [value, label] (value)}
    <button class="tab" class:active={filter === value} type="button" onclick={() => (filter = value)}>{label}</button>
  {/each}
</div>

<section class="card table-card">
  <div class="card-head"><div><h2>Loan book</h2><p>Every request this chama has recorded.</p></div><span class="status-pill purple"><i></i>{filtered.length} shown</span></div>
  {#if loading}
    <div class="skeleton-rows">{[1,2,3,4].map(() => '<div class="skeleton"></div>')}</div>
  {:else if filtered.length === 0}
    <div class="empty"><span class="empty-icon"><Icon name="loans" size={24} /></span><h3>No loans here</h3><p>Member loan requests will appear in this book.</p></div>
  {:else}
    <div class="table-wrap"><table><thead><tr><th>Borrower</th><th>Purpose</th><th>Amount</th><th>Outstanding</th><th>Repaid</th><th>Status</th><th>Requested</th></tr></thead><tbody>
      {#each filtered as loan (loan.id)}
        <tr class="clickable" onclick={() => void openLoan(loan)}>
          <td><span class="person"><span class="avatar avatar-sm">{initials(loan.borrower)}</span>{loan.borrower}</span></td>
          <td><strong>{loan.purpose}</strong><small class="muted">{loan.term_months} months · {loan.interest_rate}% {titleCase(loan.interest_method)}</small></td>
          <td class="money-cell">{money(loan.principal, group?.currency)}</td>
          <td>{money(loan.outstanding, group?.currency)}</td>
          <td><div class="repay-cell"><div class="progress small-bar"><i style={`width:${percent(number(loan.paid_to_date), number(loan.total_payable))}%`}></i></div><small>{percent(number(loan.paid_to_date), number(loan.total_payable))}%</small></div></td>
          <td><span class="status-pill {tone(loan.status)}"><i></i>{titleCase(loan.status)}</span></td>
          <td class="muted small">{dateShort(loan.requested_at)}</td>
        </tr>
      {/each}
    </tbody></table></div>
  {/if}
</section>

{#if detail}
  <div class="drawer-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) detail = null; }}>
    <div class="drawer drawer-wide" role="dialog" aria-modal="true" aria-label="Loan detail">
      <div class="drawer-head">
        <div><span class="page-kicker">Loan details</span><h2>{detail.borrower}</h2><p>{detail.purpose} · requested {dateShort(detail.requested_at)}</p></div>
        <button class="icon-btn" type="button" onclick={() => (detail = null)} aria-label="Close"><Icon name="close" size={19} /></button>
      </div>
      <div class="loan-summary">
        <div><span>Principal</span><strong>{money(detail.principal, group?.currency)}</strong></div>
        <div><span>Total payable</span><strong>{money(detail.total_payable, group?.currency)}</strong></div>
        <div><span>Paid</span><strong class="positive">{money(detail.paid_to_date, group?.currency)}</strong></div>
        <div><span>Outstanding</span><strong>{money(detail.outstanding, group?.currency)}</strong></div>
      </div>
      <div class="inline-detail"><span class="status-pill {tone(detail.status)}"><i></i>{titleCase(detail.status)}</span><span>{detail.term_months} months</span><span>{detail.interest_rate}% {titleCase(detail.interest_method)}</span><span>{money(detail.total_interest, group?.currency)} interest</span></div>
      {#if detail.guarantors.length > 0}
        <h3 class="drawer-section-title">Guarantors</h3>
        <div class="guarantor-row">{#each detail.guarantors as guarantor (guarantor.user_id)}<span class="person"><span class="avatar avatar-sm">{initials(guarantor.display_name)}</span>{guarantor.display_name}<span class="status-pill {tone(guarantor.status)}"><i></i>{titleCase(guarantor.status)}</span></span>{/each}</div>
      {/if}
      <h3 class="drawer-section-title">Repayment schedule</h3>
      {#if scheduleLoading}
        <div class="skeleton-rows">{[1,2,3].map(() => '<div class="skeleton"></div>')}</div>
      {:else if schedule.length === 0}
        <div class="empty compact"><p>The schedule is created when the loan is approved.</p></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>#</th><th>Due</th><th>Principal</th><th>Interest</th><th>Paid</th><th>Status</th></tr></thead><tbody>
          {#each schedule as item (item.installment_no)}<tr><td>{item.installment_no}</td><td>{dateShort(item.due_date)}</td><td>{money(item.principal_due, group?.currency)}</td><td>{money(item.interest_due, group?.currency)}</td><td>{money(item.paid_amount, group?.currency)}</td><td><span class="status-pill {item.paid_at ? 'green' : 'amber'}"><i></i>{item.paid_at ? 'Paid' : 'Due'}</span></td></tr>{/each}
        </tbody></table></div>
      {/if}
      <div class="drawer-actions">
        {#if manager && detail.status === 'pending_approval'}<button class="btn btn-green" type="button" onclick={() => void decide('approved')}>Approve loan</button><button class="btn btn-danger" type="button" onclick={() => void decide('rejected')}>Reject</button>{/if}
        {#if manager && detail.status === 'approved'}<button class="btn btn-green" type="button" onclick={() => openAction('disburse')}>Record disbursement</button>{/if}
        {#if manager && ['active', 'defaulted'].includes(detail.status)}<button class="btn btn-primary" type="button" onclick={() => openAction('repay')}>Record repayment</button>{/if}
        <button class="btn btn-secondary" type="button" onclick={() => (detail = null)}>Close</button>
      </div>
      {#if detail.approvals.length > 0}<p class="footnote">Last decision: {detail.approvals[detail.approvals.length - 1].display_name} · {titleCase(detail.approvals[detail.approvals.length - 1].decision)} · {dateTime(detail.approvals[detail.approvals.length - 1].created_at)}</p>{/if}
    </div>
  </div>
{/if}

{#if actionMode && detail}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) actionMode = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label={actionMode === 'disburse' ? 'Record disbursement' : 'Record repayment'}>
      <div class="modal-head"><div><h2>{actionMode === 'disburse' ? 'Record disbursement' : 'Record repayment'}</h2><p>{detail.borrower} · {detail.purpose}</p></div><button class="icon-btn" type="button" onclick={() => (actionMode = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); submitAction(); }}>
        {#if actionMode === 'repay'}<div><label for="l-amount">Amount (KES)</label><input id="l-amount" bind:value={repayAmount} inputmode="decimal" /></div>{/if}
        <div><label for="l-channel">Channel</label><select id="l-channel" bind:value={channel}><option value="mpesa_manual">M-Pesa manual</option><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="other">Other</option></select></div>
        <div><label for="l-ref">Reference (optional)</label><input id="l-ref" bind:value={reference} placeholder="M-Pesa receipt" /></div>
        <p class="secure-line"><Icon name="check" size={14} /> A PIN is required for both disbursements and repayments.</p>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (actionMode = null)}>Cancel</button><button class="btn btn-green" type="submit">{actionMode === 'disburse' ? 'Continue' : 'Record repayment'}</button></div>
      </form>
    </div>
  </div>
{/if}

{#if pinOpen}
  <PinModal title={pinTitle} subtitle={pinSubtitle} confirmLabel={actionMode === 'disburse' ? 'Record disbursement' : 'Record repayment'} onclose={() => (pinOpen = false)} onconfirm={async (token) => { if (pinAction) await pinAction(token); }} />
{/if}
