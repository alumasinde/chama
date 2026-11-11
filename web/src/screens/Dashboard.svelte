<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, canManagePayments, session } from '../lib/session.svelte';
  import { money, dateTime, number, titleCase, tone } from '../lib/format';
  import { inviteLink } from '../lib/invite';
  import type { View } from '../lib/nav';
  import type { DashboardReport, DefaulterRow, Transaction } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';
  import PayIn from './PayIn.svelte';
  import ManualPayment from './ManualPayment.svelte';

  let { onnav }: { onnav: (view: View) => void } = $props();

  const group = $derived(activeGroup());
  const canReports = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  let report = $state<DashboardReport | null>(null);
  let activity = $state<Transaction[]>([]);
  let defaulters = $state<DefaulterRow[]>([]);
  let loading = $state(true);
  let error = $state('');
  let copied = $state(false);
  let paying = $state(false);
  let recording = $state(false);

  const greeting = $derived.by(() => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  });

  const cashMax = $derived.by(() => {
    if (!report) return 1;
    return Math.max(1, ...report.cashflow.flatMap((point) => [number(point.inflow), number(point.outflow)]));
  });

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const requests: [Promise<DashboardReport>, Promise<{ data: Transaction[] }>, Promise<{ data: DefaulterRow[] }>] = [
        api<DashboardReport>(`/groups/${session.activeGroupId}/reports/dashboard`, { auth: session.access }),
        api<{ data: Transaction[] }>(`/groups/${session.activeGroupId}/transactions?limit=8`, { auth: session.access }),
        canReports
          ? api<{ data: DefaulterRow[] }>(`/groups/${session.activeGroupId}/reports/defaulters`, { auth: session.access })
          : Promise.resolve({ data: [] }),
      ];
      const [dashboard, recent, overdue] = await Promise.all(requests);
      report = dashboard;
      activity = recent.data;
      defaulters = overdue.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load the overview.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    session.access;
    void load();
  });

  async function copyInvite() {
    if (!group) return;
    try {
      await navigator.clipboard.writeText(inviteLink(group.invite_code));
      copied = true;
      window.setTimeout(() => (copied = false), 1600);
    } catch {
      copied = false;
    }
  }

  function barHeight(value: string): string {
    return `${Math.max(3, Math.round((number(value) / cashMax) * 100))}%`;
  }

  function monthLabel(bucket: string): string {
    const date = new Date(`${bucket}T00:00:00`);
    return date.toLocaleDateString('en-KE', { month: 'short' });
  }
</script>

<div class="page-head">
  <div>
    <p class="page-kicker">{new Date().toLocaleDateString('en-KE', { weekday: 'long', day: 'numeric', month: 'long' })}</p>
    <h1>{greeting}, {session.user?.first_name}</h1>
    <p>{report?.period.label ?? 'This period'} at {group?.name ?? 'your chama'}.</p>
  </div>
  <div class="page-actions">
    <button class="btn btn-secondary" type="button" onclick={() => onnav('reports')} disabled={!canReports}>
      <Icon name="reports" size={17} /> Reports
    </button>
    <button
      class="btn btn-green"
      type="button"
      onclick={() => (recording = true)}
      disabled={!canManagePayments()}
      title={canManagePayments() ? 'Record an M-Pesa receipt the treasurer already received' : 'Admins and treasurers only'}
    >
      <Icon name="plus" size={18} /> Record payment
    </button>
  </div>
</div>

{#if error}<p class="error">{error}</p>{/if}

{#if loading && !report}
  <div class="skeleton-grid">
    <div class="skeleton skeleton-hero"></div>
    <div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>
  </div>
{:else if report && group}
  <section class="balance-hero">
    <div class="hero-main">
      <div class="hero-label">Total savings <span class="live-dot"></span></div>
      <div class="hero-amount">{money(report.kpis.savings, report.group.currency)}</div>
      <div class="hero-meta">
        <span class="hero-up">+ {money(report.kpis.collected, report.group.currency)}</span>
        <span>collected in {report.period.label}</span>
      </div>
      <div class="hero-actions">
        <button class="hero-button" type="button" onclick={() => (paying = true)}>Contribute <Icon name="arrow" size={16} /></button>
        <button class="hero-link" type="button" onclick={() => onnav('chamas')}>View chama <Icon name="chevron" size={14} /></button>
      </div>
    </div>
    <div class="hero-side">
      <div class="hero-orb orb-one"></div>
      <div class="hero-orb orb-two"></div>
      <div class="hero-stamp">
        <span class="status-pill green"><i></i> Active</span>
        <span>{group.active_members} members</span>
      </div>
      <div class="hero-terms">
        <small>Contribution</small>
        <strong>{money(group.contribution_amount, group.currency)}</strong>
        <span>{titleCase(group.contribution_frequency)} · day {group.contribution_day}</span>
      </div>
    </div>
  </section>

  <div class="kpi-grid">
    <article class="kpi-card">
      <span class="kpi-icon purple"><Icon name="transactions" size={19} /></span>
      <div><span>Collected this period</span><strong>{money(report.kpis.collected, report.group.currency)}</strong></div>
      <small>{activity.filter((row) => row.status === 'completed' && row.type === 'contribution').length} recent entries</small>
    </article>
    <article class="kpi-card">
      <span class="kpi-icon amber"><Icon name="loans" size={19} /></span>
      <div><span>Outstanding loans</span><strong>{money(report.kpis.outstanding_loans, report.group.currency)}</strong></div>
      <small>{report.kpis.pending_loans} waiting for approval</small>
    </article>
    <article class="kpi-card">
      <span class="kpi-icon red"><Icon name="fines" size={19} /></span>
      <div><span>Fines unpaid</span><strong>{money(report.kpis.unpaid_fines, report.group.currency)}</strong></div>
      <small>Charged but not yet settled</small>
    </article>
    <article class="kpi-card">
      <span class="kpi-icon green"><Icon name="members" size={19} /></span>
      <div><span>Active members</span><strong>{report.kpis.active_members}</strong></div>
      <small>{money(report.kpis.welfare_balance, report.group.currency)} in welfare</small>
    </article>
  </div>

  {#if defaulters.length > 0}
    <button class="attention-strip" type="button" onclick={() => onnav('reports')}>
      <span class="attention-icon"><Icon name="fines" size={18} /></span>
      <span><strong>{defaulters.length} overdue loan {defaulters.length === 1 ? 'account' : 'accounts'}</strong><small>Oldest payment is {defaulters[0].days_overdue} days late · {money(defaulters[0].amount_due, report.group.currency)} due</small></span>
      <Icon name="chevron" size={17} />
    </button>
  {/if}

  <div class="overview-grid">
    <section class="card chart-card">
      <div class="card-head">
        <div><h2>Cash flow</h2><p>Collected against money paid out</p></div>
        <span class="segmented"><span class="seg active">6 months</span></span>
      </div>
      {#if report.cashflow.length === 0}
        <div class="empty compact"><p>No completed ledger entries yet.</p></div>
      {:else}
        <div class="chart-legend"><span><i class="legend-in"></i> Inflow</span><span><i class="legend-out"></i> Outflow</span></div>
        <div class="bar-chart">
          {#each report.cashflow as point (point.bucket)}
            <div class="bar-group">
              <div class="bars">
                <span class="bar in" style={`height:${barHeight(point.inflow)}`} title={`In ${money(point.inflow)}`}></span>
                <span class="bar out" style={`height:${barHeight(point.outflow)}`} title={`Out ${money(point.outflow)}`}></span>
              </div>
              <small>{monthLabel(point.bucket)}</small>
            </div>
          {/each}
        </div>
      {/if}
    </section>

    <section class="card terms-card">
      <div class="card-head"><div><h2>Next contribution</h2><p>Your group's current terms</p></div><span class="date-chip">{report.period.label}</span></div>
      <div class="due-amount">{money(report.group.contribution_amount, report.group.currency)}</div>
      <p class="muted small">Due day {group.contribution_day} · {group.late_grace_days} day grace before a late fine.</p>
      <div class="terms-list">
        <div><span>Frequency</span><strong>{titleCase(group.contribution_frequency)}</strong></div>
        <div><span>Invite code</span><strong class="mono">{group.invite_code}</strong></div>
        <div><span>Your role</span><strong>{titleCase(group.role)}</strong></div>
      </div>
      <div class="terms-actions">
        <button class="btn btn-primary full-width" type="button" onclick={() => (paying = true)}>Pay via M-Pesa</button>
        <button class="btn btn-ghost full-width" type="button" onclick={copyInvite}>{copied ? 'Invite link copied' : 'Copy invite link'}</button>
      </div>
    </section>
  </div>

  <section class="quick-grid">
    <button class="quick-tile" type="button" onclick={() => (paying = true)}><span class="quick-icon purple"><Icon name="plus" size={20} /></span><strong>Contribute</strong><small>Record a payment</small></button>
    <button class="quick-tile" type="button" onclick={() => onnav('members')}><span class="quick-icon green"><Icon name="members" size={20} /></span><strong>Members</strong><small>Approve and manage</small></button>
    <button class="quick-tile" type="button" onclick={() => onnav('loans')}><span class="quick-icon amber"><Icon name="loans" size={20} /></span><strong>Loans</strong><small>Book and schedules</small></button>
    <button class="quick-tile" type="button" onclick={() => onnav('welfare')}><span class="quick-icon pink"><Icon name="welfare" size={20} /></span><strong>Welfare</strong><small>Fund and claims</small></button>
  </section>

  <section class="card table-card">
    <div class="card-head">
      <div><h2>Recent activity</h2><p>Every entry is part of the chama ledger.</p></div>
      <div class="card-tools">
        {#if canReports}<ExportButtons reportCode="transactions" compact />{/if}
        <button class="btn btn-ghost" type="button" onclick={() => onnav('transactions')}>View all</button>
      </div>
    </div>
    {#if activity.length === 0}
      <div class="empty"><span class="empty-icon"><Icon name="transactions" size={24} /></span><h3>No entries yet</h3><p>Use Record payment to make the first contribution.</p></div>
    {:else}
      <div class="table-wrap">
        <table>
          <thead><tr><th>When</th><th>Member</th><th>Purpose</th><th>Amount</th><th>Status</th><th>Reference</th></tr></thead>
          <tbody>
            {#each activity as entry (entry.id)}
              <tr>
                <td class="muted small nowrap">{dateTime(entry.created_at)}</td>
                <td><span class="person"><span class="avatar avatar-sm">{entry.member.split(' ').map((part) => part[0]).slice(0,2).join('')}</span>{entry.member}</span></td>
                <td>{titleCase(entry.type)}</td>
                <td class="money-cell">{money(entry.amount, report.group.currency)}</td>
                <td><span class="status-pill {tone(entry.status)}"><i></i>{titleCase(entry.status)}</span></td>
                <td class="muted small mono">{entry.reference_code ?? '—'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </section>
{:else}
  <div class="card empty"><h3>Select a chama</h3></div>
{/if}

{#if paying}
  <PayIn onclose={() => { paying = false; void load(); }} />
{/if}

{#if recording}
  <ManualPayment onclose={() => { recording = false; void load(); }} onrecorded={() => void load()} />
{/if}
