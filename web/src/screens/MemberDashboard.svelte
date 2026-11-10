<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, dateShort, dateTime, number, titleCase, tone, initials } from '../lib/format';
  import type { View } from '../lib/nav';
  import type { MyRotation, RotationCycle, Transaction, WelfareClaim, WelfareContribution, WelfareFund } from '../lib/types';
  import Icon from '../components/Icon.svelte';

  let { onnav }: { onnav: (view: View) => void } = $props();
  const group = $derived(activeGroup());
  let fund = $state<WelfareFund | null>(null);
  let contributions = $state<WelfareContribution[]>([]);
  let claims = $state<WelfareClaim[]>([]);
  let cycles = $state<RotationCycle[]>([]);
  let myRotations = $state<MyRotation[]>([]);
  let transactions = $state<Transaction[]>([]);
  let loading = $state(true);
  let error = $state('');

  const contributionsTotal = $derived(contributions.reduce((total, row) => total + number(row.amount), 0));
  const savings = $derived(transactions.filter((row) => row.type === 'contribution' && row.status === 'completed').reduce((total, row) => total + number(row.amount), 0));
  const completedContributions = $derived(transactions.filter((row) => row.type === 'contribution' && row.status === 'completed').length);
  const pendingClaims = $derived(claims.filter((claim) => claim.status === 'pending'));
  const latestClaim = $derived(claims[0] ?? null);
  const activeCycle = $derived(cycles.find((cycle) => cycle.status === 'active') ?? cycles.find((cycle) => cycle.status === 'draft') ?? null);
  const rotation = $derived.by(() => {
    const direct = myRotations.find((row) => row.group_id === group?.id);
    if (direct) return direct;
    const cycle = activeCycle;
    const slot = cycle?.slots.find((row) => row.user_id === session.user?.id);
    if (!cycle || !slot) return null;
    return {
      group_id: group?.id ?? '', group_name: group?.name ?? '', cycle_id: cycle.id, cycle_name: cycle.name,
      position: slot.position, payout_date: slot.payout_date, paid: slot.paid,
    } satisfies MyRotation;
  });
  const myCurrentContribution = $derived(contributions.find((row) => row.period_label === new Date().toISOString().slice(0, 7)) ?? contributions[0] ?? null);

  const greeting = $derived.by(() => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  });

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const [fundView, contributionRows, claimRows, cycleRows, rotationRows, ledger] = await Promise.all([
        api<WelfareFund>(`/groups/${session.activeGroupId}/welfare`, { auth: session.access }),
        api<{ data: WelfareContribution[] }>(`/groups/${session.activeGroupId}/welfare/contributions?limit=100`, { auth: session.access }),
        api<{ data: WelfareClaim[] }>(`/groups/${session.activeGroupId}/welfare/claims?limit=100`, { auth: session.access }),
        api<{ data: RotationCycle[] }>(`/groups/${session.activeGroupId}/rotation/cycles?limit=20`, { auth: session.access }),
        api<{ data: MyRotation[] }>('/me/rotation?limit=20', { auth: session.access }),
        api<{ data: Transaction[] }>(`/groups/${session.activeGroupId}/transactions?limit=100`, { auth: session.access }),
      ]);
      fund = fundView;
      contributions = contributionRows.data.filter((row) => row.user_id === session.user?.id);
      claims = claimRows.data.filter((row) => row.user_id === session.user?.id);
      cycles = cycleRows.data;
      myRotations = rotationRows.data;
      transactions = ledger.data.filter((row) => row.user_id === session.user?.id);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load your overview.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    session.access;
    void load();
  });
</script>

<div class="page-head">
  <div><p class="page-kicker">Your account</p><h1>Your chama at a glance</h1><p>Your savings, welfare, rotation turn and personal ledger — no committee controls.</p></div>
  <div class="page-actions"><span class="status-pill purple"><i></i>Member view</span></div>
</div>

{#if error}<p class="error">{error}</p>{/if}

{#if loading && !fund}
  <div class="skeleton-grid"><div class="skeleton skeleton-hero"></div><div class="skeleton"></div><div class="skeleton"></div></div>
{:else if group}
  <section class="balance-hero member-hero">
    <div class="hero-main">
      <div class="hero-label">{greeting}, {session.user?.first_name} <span class="live-dot"></span></div>
      <div class="hero-amount">{money(savings, group.currency)}</div>
      <div class="hero-meta"><span>{completedContributions} completed contribution{completedContributions === 1 ? '' : 's'} in {group.name}</span></div>
      <div class="hero-actions">
        <button class="hero-button" type="button" onclick={() => onnav('transactions')}>Your ledger <Icon name="arrow" size={16} /></button>
        <button class="hero-link" type="button" onclick={() => onnav('welfare')}>Welfare <Icon name="chevron" size={14} /></button>
        <button class="hero-link" type="button" onclick={() => onnav('rotation')}>Rotation <Icon name="chevron" size={14} /></button>
      </div>
    </div>
    <div class="hero-side">
      <div class="hero-stamp"><span class="status-pill green"><i></i> Active</span><span>{titleCase(group.role)}</span></div>
      <div class="hero-terms"><small>Contribution</small><strong>{money(group.contribution_amount, group.currency)}</strong><span>{titleCase(group.contribution_frequency)} · day {group.contribution_day}</span></div>
    </div>
  </section>

  <div class="kpi-grid">
    <article class="kpi-card"><span class="kpi-icon green"><Icon name="welfare" size={19} /></span><div><span>Your welfare</span><strong>{money(contributionsTotal, group.currency)}</strong></div><small>{fund?.configured ? `${money(fund.balance, group.currency)} in the group fund` : 'Fund not set up yet'}</small></article>
    <article class="kpi-card"><span class="kpi-icon purple"><Icon name="rotation" size={19} /></span><div><span>Your rotation turn</span><strong>{rotation ? `#${rotation.position}` : '—'}</strong></div><small>{rotation ? `${rotation.paid ? 'Paid' : 'Expected'} ${dateShort(rotation.payout_date)}` : 'No active cycle'}</small></article>
    <article class="kpi-card"><span class="kpi-icon amber"><Icon name="fines" size={19} /></span><div><span>Open claims</span><strong>{pendingClaims.length}</strong></div><small>{latestClaim ? `Latest: ${titleCase(latestClaim.status)}` : 'No welfare claims'}</small></article>
    <article class="kpi-card"><span class="kpi-icon pink"><Icon name="transactions" size={19} /></span><div><span>Recent entries</span><strong>{transactions.length}</strong></div><small>Only your personal ledger rows</small></article>
  </div>

  <div class="split-grid">
    <section class="card pad">
      <div class="card-head"><div><h2>Your rotation position</h2><p>Where you sit in the current merry-go-round.</p></div><span class="kpi-icon purple"><Icon name="rotation" size={20} /></span></div>
      {#if rotation}
        <div class="member-rotation">
          <div class="position-badge">#{rotation.position}</div>
          <div><strong>{rotation.cycle_name}</strong><p>{rotation.paid ? 'Your payout has been recorded.' : `Expected around ${dateShort(rotation.payout_date)}.`}</p><span class="status-pill {rotation.paid ? 'green' : 'amber'}"><i></i>{rotation.paid ? 'Paid' : 'Waiting'}</span></div>
        </div>
      {:else}
        <div class="empty compact"><p>You are not in an active rotation yet. Ask your committee when the next cycle opens.</p></div>
      {/if}
      <button class="btn btn-secondary full-width" type="button" onclick={() => onnav('rotation')}>View rotation</button>
    </section>

    <section class="card pad">
      <div class="card-head"><div><h2>Welfare cover</h2><p>Your contributions and latest request.</p></div><span class="kpi-icon green"><Icon name="welfare" size={20} /></span></div>
      <div class="detail-list">
        <div><span>Your contributions</span><strong>{money(contributionsTotal, group.currency)}</strong></div>
        <div><span>This period</span><strong>{myCurrentContribution ? money(myCurrentContribution.amount, group.currency) : 'Not recorded'}</strong></div>
        <div><span>Open claims</span><strong>{pendingClaims.length}</strong></div>
        <div><span>Latest claim</span><strong>{latestClaim ? `${money(latestClaim.amount, group.currency)} · ${titleCase(latestClaim.status)}` : 'None'}</strong></div>
      </div>
      {#if latestClaim}<p class="footnote">Requested {dateShort(latestClaim.requested_at)}{latestClaim.comment ? ` · ${latestClaim.comment}` : ''}.</p>{:else}<p class="footnote">You can request welfare support from the welfare screen.</p>{/if}
      <button class="btn btn-secondary full-width" type="button" onclick={() => onnav('welfare')}>Open welfare</button>
    </section>
  </div>

  <section class="card table-card">
    <div class="card-head"><div><h2>Your personal ledger</h2><p>Contributions, payouts and repayments that belong to you.</p></div><button class="btn btn-ghost" type="button" onclick={() => onnav('transactions')}>View all</button></div>
    {#if transactions.length === 0}
      <div class="empty"><span class="empty-icon"><Icon name="transactions" size={24} /></span><h3>No personal entries yet</h3><p>Your completed contributions and payouts will appear here.</p></div>
    {:else}
      <div class="table-wrap"><table><thead><tr><th>When</th><th>Purpose</th><th>Amount</th><th>Status</th><th>Reference</th></tr></thead><tbody>
        {#each transactions.slice(0, 8) as row (row.id)}
          <tr><td class="muted small nowrap">{dateTime(row.created_at)}</td><td><strong>{titleCase(row.type)}</strong><div class="muted small">{row.narration}</div></td><td class="money-cell">{money(row.amount, group.currency)}</td><td><span class="status-pill {tone(row.status)}"><i></i>{titleCase(row.status)}</span></td><td class="muted small mono">{row.reference_code ?? '—'}</td></tr>
        {/each}
      </tbody></table></div>
    {/if}
  </section>

  <p class="footnote"><Icon name="check" size={13} /> This view is read-only. Committee approvals, settings, exports and member management are available only to authorised roles.</p>
{:else}
  <div class="card empty"><h3>Select a chama</h3></div>
{/if}
