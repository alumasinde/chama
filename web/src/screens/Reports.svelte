<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, dateShort, dateTime, number, titleCase, tone } from '../lib/format';
  import { downloadJob } from '../lib/reports';
  import type { DashboardReport, DefaulterRow, LoanBookRow, ReportFineRow, ReportJob } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';

  const group = $derived(activeGroup());
  let report = $state<DashboardReport | null>(null);
  let loanBook = $state<LoanBookRow[]>([]);
  let defaulters = $state<DefaulterRow[]>([]);
  let fines = $state<ReportFineRow[]>([]);
  let jobs = $state<ReportJob[]>([]);
  let loading = $state(true);
  let error = $state('');
  let tab = $state<'overview' | 'loans' | 'defaulters' | 'fines' | 'exports'>('overview');
  let downloading = $state('');

  const exportsList = [
    { code: 'transactions', title: 'Transactions', body: 'Every ledger entry with member, purpose, amount, status and reference.', icon: 'transactions' },
    { code: 'members', title: 'Members', body: 'The member directory with roles, status and join dates.', icon: 'members' },
    { code: 'loan_book', title: 'Loan book', body: 'Principal, total payable, paid and outstanding by borrower.', icon: 'loans' },
    { code: 'defaulters', title: 'Overdue loans', body: 'Missed installments grouped by loan, with days late and amount due.', icon: 'fines' },
    { code: 'fines', title: 'Fines', body: 'Assessed fines, status, period and reason.', icon: 'fines' },
    { code: 'welfare_contributions', title: 'Welfare contributions', body: 'Per-member welfare payments and periods.', icon: 'welfare' },
    { code: 'welfare_claims', title: 'Welfare claims', body: 'Claims, decisions and payout status.', icon: 'welfare' },
    { code: 'rotation', title: 'Rotation schedule', body: 'Every turn, payout date and paid status.', icon: 'rotation' },
    { code: 'audit', title: 'Audit trail', body: 'Actor, action, entity and before/after values.', icon: 'audit' },
  ];

  const cashMax = $derived.by(() => {
    if (!report) return 1;
    return Math.max(1, ...report.cashflow.flatMap((point) => [number(point.inflow), number(point.outflow)]));
  });

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const [dashboard, loans, overdue, fineRows, jobRows] = await Promise.all([
        api<DashboardReport>(`/groups/${session.activeGroupId}/reports/dashboard`, { auth: session.access }),
        api<{ data: LoanBookRow[] }>(`/groups/${session.activeGroupId}/reports/loan-book`, { auth: session.access }),
        api<{ data: DefaulterRow[] }>(`/groups/${session.activeGroupId}/reports/defaulters`, { auth: session.access }),
        api<{ data: ReportFineRow[] }>(`/groups/${session.activeGroupId}/reports/fines`, { auth: session.access }),
        api<{ data: ReportJob[] }>(`/groups/${session.activeGroupId}/reports/jobs?limit=30`, { auth: session.access }),
      ]);
      report = dashboard;
      loanBook = loans.data;
      defaulters = overdue.data;
      fines = fineRows.data;
      jobs = jobRows.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load reports.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  function barHeight(value: string): string {
    return `${Math.max(3, Math.round((number(value) / cashMax) * 100))}%`;
  }

  function monthLabel(bucket: string): string {
    return new Date(`${bucket}T00:00:00`).toLocaleDateString('en-KE', { month: 'short' });
  }

  async function saveJob(job: ReportJob) {
    downloading = job.id;
    error = '';
    try {
      await downloadJob(job);
    } catch (err) {
      error = err instanceof ApiFailure || err instanceof Error ? err.message : 'Could not download that report.';
    } finally {
      downloading = '';
    }
  }

  async function refreshJobs() {
    if (!session.activeGroupId || !session.access) return;
    try {
      const result = await api<{ data: ReportJob[] }>(`/groups/${session.activeGroupId}/reports/jobs?limit=30`, { auth: session.access });
      jobs = result.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not refresh exports.';
    }
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Numbers that hold up</p><h1>Reports</h1><p>Live ledger totals and downloads that open cleanly in Excel or a PDF reader.</p></div>
  <div class="page-actions"><button class="btn btn-secondary" type="button" onclick={() => void load()}><Icon name="refresh" size={16} /> Refresh</button><ExportButtons reportCode="transactions" /></div>
</div>

{#if error}<p class="error">{error}</p>{/if}

<div class="tab-bar">
  <button class="tab" class:active={tab === 'overview'} type="button" onclick={() => (tab = 'overview')}>Overview</button>
  <button class="tab" class:active={tab === 'loans'} type="button" onclick={() => (tab = 'loans')}>Loan book <span>{loanBook.length}</span></button>
  <button class="tab" class:active={tab === 'defaulters'} type="button" onclick={() => (tab = 'defaulters')}>Overdue <span>{defaulters.length}</span></button>
  <button class="tab" class:active={tab === 'fines'} type="button" onclick={() => (tab = 'fines')}>Fines</button>
  <button class="tab" class:active={tab === 'exports'} type="button" onclick={() => (tab = 'exports')}>Exports <span>{jobs.length}</span></button>
</div>

{#if loading && !report}
  <div class="skeleton-grid"><div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div></div>
{:else if report}
  {#if tab === 'overview'}
    <div class="kpi-grid">
      <article class="kpi-card"><span class="kpi-icon purple"><Icon name="transactions" size={19} /></span><div><span>Savings</span><strong>{money(report.kpis.savings, report.group.currency)}</strong></div><small>All completed contributions</small></article>
      <article class="kpi-card"><span class="kpi-icon amber"><Icon name="loans" size={19} /></span><div><span>Outstanding</span><strong>{money(report.kpis.outstanding_loans, report.group.currency)}</strong></div><small>{report.kpis.pending_loans} pending requests</small></article>
      <article class="kpi-card"><span class="kpi-icon red"><Icon name="fines" size={19} /></span><div><span>Fines unpaid</span><strong>{money(report.kpis.unpaid_fines, report.group.currency)}</strong></div><small>{fines.filter((fine) => fine.status === 'unpaid').length} open fines</small></article>
      <article class="kpi-card"><span class="kpi-icon green"><Icon name="welfare" size={19} /></span><div><span>Welfare balance</span><strong>{money(report.kpis.welfare_balance, report.group.currency)}</strong></div><small>{report.kpis.active_members} active members</small></article>
    </div>

    <div class="report-grid">
      <section class="card chart-card">
        <div class="card-head"><div><h2>Collections vs payouts</h2><p>Last six months, completed entries only.</p></div><span class="date-chip">{report.period.label}</span></div>
        <div class="chart-legend"><span><i class="legend-in"></i> Inflow</span><span><i class="legend-out"></i> Outflow</span></div>
        {#if report.cashflow.length === 0}
          <div class="empty compact"><p>No completed transactions yet.</p></div>
        {:else}
          <div class="bar-chart wide">
            {#each report.cashflow as point (point.bucket)}
              <div class="bar-group"><div class="bars"><span class="bar in" style={`height:${barHeight(point.inflow)}`} title={money(point.inflow)}></span><span class="bar out" style={`height:${barHeight(point.outflow)}`} title={money(point.outflow)}></span></div><small>{monthLabel(point.bucket)}</small></div>
            {/each}
          </div>
        {/if}
      </section>
      <section class="card pad export-teaser">
        <span class="kpi-icon purple"><Icon name="download" size={21} /></span>
        <h2>Take the ledger with you</h2>
        <p>CSV files include a UTF-8 BOM so Excel reads names and shillings correctly. Amounts stay as plain 2dp numbers, not formulas.</p>
        <button class="btn btn-primary full-width" type="button" onclick={() => (tab = 'exports')}>Open exports</button>
        <p class="footnote">Only admins, treasurers and secretaries can generate group files.</p>
      </section>
    </div>

    <section class="card table-card">
      <div class="card-head"><div><h2>Overdue attention</h2><p>{defaulters.length ? 'These loans have missed at least one installment.' : 'No loans are overdue.'}</p></div><button class="btn btn-ghost" type="button" onclick={() => (tab = 'defaulters')}>See all</button></div>
      {#if defaulters.length === 0}
        <div class="empty compact"><span class="status-pill green"><i></i>All caught up</span></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>Borrower</th><th>Oldest due</th><th>Days late</th><th>Amount due</th><th>Status</th></tr></thead><tbody>
          {#each defaulters.slice(0, 5) as row (row.loan_id)}
            <tr><td><strong>{row.borrower}</strong></td><td>{dateShort(row.oldest_due)}</td><td><span class="status-pill red"><i></i>{row.days_overdue} days</span></td><td class="money-cell">{money(row.amount_due, report?.group.currency)}</td><td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td></tr>
          {/each}
        </tbody></table></div>
      {/if}
    </section>
  {:else if tab === 'loans'}
    <section class="card table-card">
      <div class="card-head"><div><h2>Loan book</h2><p>Every loan with its current balance.</p></div><ExportButtons reportCode="loan_book" /></div>
      {#if loanBook.length === 0}
        <div class="empty"><span class="empty-icon"><Icon name="loans" size={24} /></span><h3>The loan book is empty</h3><p>No member has requested a loan yet.</p></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>Borrower</th><th>Status</th><th>Principal</th><th>Total payable</th><th>Paid</th><th>Outstanding</th><th>Next due</th></tr></thead><tbody>
          {#each loanBook as row (row.id)}
            <tr><td><strong>{row.borrower}</strong><small class="muted">Requested {dateShort(row.requested_at)}</small></td><td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td><td>{money(row.principal, report.group.currency)}</td><td>{money(row.total_payable, report.group.currency)}</td><td class="positive">{money(row.paid, report.group.currency)}</td><td class="money-cell">{money(row.outstanding, report.group.currency)}</td><td>{row.next_due ? dateShort(row.next_due) : '—'}</td></tr>
          {/each}
        </tbody></table></div>
      {/if}
    </section>
  {:else if tab === 'defaulters'}
    <section class="card table-card">
      <div class="card-head"><div><h2>Overdue loans</h2><p>Unpaid installments past their due date.</p></div><ExportButtons reportCode="defaulters" /></div>
      {#if defaulters.length === 0}
        <div class="empty"><span class="status-pill green"><i></i>No overdue loans</span></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>Borrower</th><th>Loan</th><th>Oldest due</th><th>Days overdue</th><th>Amount due</th><th>Status</th></tr></thead><tbody>
          {#each defaulters as row (row.loan_id)}
            <tr><td><strong>{row.borrower}</strong></td><td class="mono small">{row.loan_id.slice(0, 8)}</td><td>{dateShort(row.oldest_due)}</td><td><span class="status-pill red"><i></i>{row.days_overdue} days</span></td><td class="money-cell">{money(row.amount_due, report.group.currency)}</td><td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td></tr>
          {/each}
        </tbody></table></div>
      {/if}
    </section>
  {:else if tab === 'fines'}
    <section class="card table-card">
      <div class="card-head"><div><h2>Fines report</h2><p>Assessed fines and their settlement state.</p></div><ExportButtons reportCode="fines" /></div>
      {#if fines.length === 0}
        <div class="empty"><span class="empty-icon"><Icon name="fines" size={24} /></span><h3>No fines assessed</h3><p>Fines raised by your rules will appear here.</p></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>Member</th><th>Type</th><th>Period</th><th>Amount</th><th>Assessed</th><th>Status</th></tr></thead><tbody>
          {#each fines as row (row.id)}
            <tr><td><strong>{row.member}</strong><small class="muted">{row.reason}</small></td><td>{titleCase(row.fine_type)}</td><td class="mono">{row.period_label || '—'}</td><td class="money-cell">{money(row.amount, report.group.currency)}</td><td>{dateShort(row.assessed_on)}</td><td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td></tr>
          {/each}
        </tbody></table></div>
      {/if}
    </section>
  {:else}
    <section class="export-grid">
      {#each exportsList as item (item.code)}
        <article class="export-card">
          <span class="kpi-icon purple"><Icon name={item.icon} size={20} /></span>
          <h3>{item.title}</h3>
          <p>{item.body}</p>
          <ExportButtons reportCode={item.code} compact />
        </article>
      {/each}
    </section>
    <section class="card table-card">
      <div class="card-head"><div><h2>Export history</h2><p>Generated files remain available for this chama.</p></div><button class="btn btn-ghost" type="button" onclick={() => void refreshJobs()}><Icon name="refresh" size={15} /> Refresh</button></div>
      {#if jobs.length === 0}
        <div class="empty"><span class="empty-icon"><Icon name="download" size={24} /></span><h3>No exports yet</h3><p>Choose a report above to create the first file.</p></div>
      {:else}
        <div class="table-wrap"><table><thead><tr><th>Report</th><th>Format</th><th>Rows</th><th>Created</th><th>Status</th><th></th></tr></thead><tbody>
          {#each jobs as job (job.id)}
            <tr><td><strong>{titleCase(job.report_code)}</strong><small class="muted mono">{job.file_name}</small></td><td><span class="format-chip">{job.format.toUpperCase()}</span></td><td>{job.row_count}</td><td class="muted small">{dateTime(job.created_at)}</td><td><span class="status-pill {tone(job.status)}"><i></i>{titleCase(job.status)}</span></td><td class="align-right"><button class="btn btn-small btn-secondary" type="button" onclick={() => void saveJob(job)} disabled={downloading === job.id || job.status !== 'done'}><Icon name="download" size={14} /> {downloading === job.id ? 'Saving…' : 'Download'}</button></td></tr>
          {/each}
        </tbody></table></div>
      {/if}
    </section>
  {/if}
{/if}
