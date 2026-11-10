<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, dateTime, number, titleCase, tone } from '../lib/format';
  import type { Transaction } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';

  const group = $derived(activeGroup());
  const canExport = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  let rows = $state<Transaction[]>([]);
  let loading = $state(true);
  let error = $state('');
  let type = $state('all');
  let status = $state('all');
  let search = $state('');

  const filtered = $derived(rows.filter((row) => {
    if (type !== 'all' && row.type !== type) return false;
    if (status !== 'all' && row.status !== status) return false;
    if (search.trim() && !`${row.member} ${row.reference_code ?? ''} ${row.narration}`.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  }));

  const collected = $derived(filtered.filter((row) => row.status === 'completed' && ['contribution', 'welfare_contribution', 'fine', 'loan_repayment'].includes(row.type)).reduce((total, row) => total + number(row.amount), 0));
  const paidOut = $derived(filtered.filter((row) => row.status === 'completed' && ['loan_disbursement', 'welfare_payout', 'rotation_payout'].includes(row.type)).reduce((total, row) => total + number(row.amount), 0));
  const pending = $derived(rows.filter((row) => row.status === 'pending').length);

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const result = await api<{ data: Transaction[] }>(`/groups/${session.activeGroupId}/transactions?limit=100`, { auth: session.access });
      rows = result.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load transactions.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });
</script>

<div class="page-head">
  <div><p class="page-kicker">Ledger</p><h1>Transactions</h1><p>Contributions, repayments and payouts recorded against {group?.name}.</p></div>
  <div class="page-actions">{#if canExport}<ExportButtons reportCode="transactions" />{/if}<button class="btn btn-secondary" type="button" onclick={() => void load()}><Icon name="refresh" size={16} /> Refresh</button></div>
</div>

{#if error}<p class="error">{error}</p>{/if}

<div class="summary-row">
  <div><span>Money in</span><strong class="positive">{money(collected, group?.currency)}</strong></div>
  <div><span>Money out</span><strong>{money(paidOut, group?.currency)}</strong></div>
  <div><span>Ledger entries</span><strong>{filtered.length}</strong></div>
  <div><span>Awaiting settlement</span><strong>{pending}</strong></div>
</div>

<section class="card table-card">
  <div class="filter-bar">
    <label class="search-field"><Icon name="search" size={16} /><input bind:value={search} placeholder="Search member or reference" aria-label="Search transactions" /></label>
    <select bind:value={type} aria-label="Filter by type">
      <option value="all">All purposes</option>
      <option value="contribution">Contribution</option>
      <option value="welfare_contribution">Welfare</option>
      <option value="loan_repayment">Loan repayment</option>
      <option value="fine">Fine</option>
      <option value="loan_disbursement">Loan payout</option>
      <option value="welfare_payout">Welfare payout</option>
      <option value="rotation_payout">Rotation payout</option>
    </select>
    <select bind:value={status} aria-label="Filter by status">
      <option value="all">All statuses</option>
      <option value="completed">Completed</option>
      <option value="pending">Pending</option>
      <option value="failed">Failed</option>
      <option value="reversed">Reversed</option>
    </select>
    <span class="filter-count">{filtered.length} shown</span>
  </div>

  {#if loading}
    <div class="skeleton-rows">{[1,2,3,4,5].map(() => '<div class="skeleton"></div>')}</div>
  {:else if filtered.length === 0}
    <div class="empty"><span class="empty-icon"><Icon name="search" size={24} /></span><h3>No matching entries</h3><p>Try another purpose or status.</p></div>
  {:else}
    <div class="table-wrap">
      <table>
        <thead><tr><th>When</th><th>Member</th><th>Purpose</th><th>Channel</th><th>Amount</th><th>Status</th><th>Reference</th></tr></thead>
        <tbody>
          {#each filtered as row (row.id)}
            <tr>
              <td class="muted small nowrap">{dateTime(row.created_at)}</td>
              <td><span class="person"><span class="avatar avatar-sm">{row.member.split(' ').map((part) => part[0]).slice(0,2).join('')}</span>{row.member}</span></td>
              <td><strong>{titleCase(row.type)}</strong><div class="muted small">{row.narration}</div></td>
              <td class="muted small">{titleCase(row.channel)}</td>
              <td class="money-cell">{money(row.amount, group?.currency)}</td>
              <td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td>
              <td class="muted small mono">{row.reference_code ?? '—'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>
