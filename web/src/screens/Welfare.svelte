<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, dateShort, dateTime, titleCase, tone, initials } from '../lib/format';
  import type { Member, WelfareClaim, WelfareContribution, WelfareFund } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';
  import PinModal from '../components/PinModal.svelte';

  const group = $derived(activeGroup());
  const manager = $derived(['admin', 'treasurer'].includes(group?.role ?? ''));
  let fund = $state<WelfareFund | null>(null);
  let contributions = $state<WelfareContribution[]>([]);
  let claims = $state<WelfareClaim[]>([]);
  let members = $state<Member[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let tab = $state<'overview' | 'contributions' | 'claims'>('overview');
  let modal = $state<'setup' | 'contribution' | 'claim' | 'decision' | 'payout' | null>(null);
  let targetClaim = $state<WelfareClaim | null>(null);

  let fundName = $state('Welfare fund');
  let monthly = $state('0.00');
  let active = $state(true);
  let memberID = $state('');
  let amount = $state('');
  let period = $state(new Date().toISOString().slice(0, 7));
  let channel = $state('mpesa_manual');
  let reference = $state('');
  let reason = $state('');
  let decision = $state('approved');
  let comment = $state('');

  let pinOpen = $state(false);
  let pinTitle = $state('Confirm with your PIN');
  let pinSubtitle = $state('Your PIN authorises this welfare entry.');
  let pinAction: ((token: string) => Promise<void>) | null = $state(null);
  let busy = $state(false);

  const pendingClaims = $derived(claims.filter((claim) => claim.status === 'pending'));
  const approvedClaims = $derived(claims.filter((claim) => claim.status === 'approved'));

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const [fundResult, contributionResult, claimResult, memberResult] = await Promise.all([
        api<WelfareFund>(`/groups/${session.activeGroupId}/welfare`, { auth: session.access }),
        api<{ data: WelfareContribution[] }>(`/groups/${session.activeGroupId}/welfare/contributions?limit=100`, { auth: session.access }),
        api<{ data: WelfareClaim[] }>(`/groups/${session.activeGroupId}/welfare/claims?limit=100`, { auth: session.access }),
        api<{ data: Member[] }>(`/groups/${session.activeGroupId}/members`, { auth: session.access }),
      ]);
      fund = fundResult;
      contributions = contributionResult.data;
      claims = claimResult.data;
      members = memberResult.data.filter((member) => member.status === 'active');
      if (fundResult.configured) {
        fundName = fundResult.name;
        monthly = fundResult.monthly_amount;
        active = fundResult.is_active;
        if (!amount) amount = fundResult.monthly_amount;
      }
      if (!memberID && members.length > 0) {
        memberID = members.find((member) => member.user_id === session.user?.id)?.user_id ?? members[0].user_id;
      }
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load the welfare fund.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  function openSetup() {
    if (fund?.configured) {
      fundName = fund.name;
      monthly = fund.monthly_amount;
      active = fund.is_active;
    }
    modal = 'setup';
  }

  function openContribution() {
    amount = fund?.monthly_amount || '';
    period = new Date().toISOString().slice(0, 7);
    channel = 'mpesa_manual';
    reference = '';
    modal = 'contribution';
  }

  function openClaim() {
    amount = '';
    reason = '';
    modal = 'claim';
  }

  function openDecision(claim: WelfareClaim) {
    targetClaim = claim;
    decision = 'approved';
    comment = '';
    modal = 'decision';
  }

  function openPayout(claim: WelfareClaim) {
    targetClaim = claim;
    channel = 'mpesa_manual';
    reference = '';
    modal = 'payout';
  }

  async function saveFund() {
    if (!session.activeGroupId || !session.access) return;
    busy = true;
    error = '';
    notice = '';
    try {
      fund = await api<WelfareFund>(`/groups/${session.activeGroupId}/welfare`, {
        method: 'PUT', auth: session.access,
        body: { name: fundName, monthly_amount: monthly, is_active: active },
      });
      modal = null;
      notice = 'Welfare fund settings saved.';
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not save the welfare fund.';
    } finally {
      busy = false;
    }
  }

  function pinThen(title: string, subtitle: string, action: (token: string) => Promise<void>) {
    pinTitle = title;
    pinSubtitle = subtitle;
    pinAction = async (token) => {
      await action(token);
      pinOpen = false;
    };
    pinOpen = true;
  }

  function submitContribution() {
    if (!session.activeGroupId || !session.access) return;
    pinThen('Record welfare contribution', 'This writes a completed ledger entry for the selected member.', async (token) => {
      await api(`/groups/${session.activeGroupId}/welfare/contributions`, {
        method: 'POST', auth: session.access,
        headers: { 'X-Step-Up-Token': token, 'Idempotency-Key': crypto.randomUUID() },
        body: {
          user_id: memberID, amount, period_label: period, channel,
          ...(reference.trim() ? { reference: reference.trim() } : {}),
        },
      });
      modal = null;
      notice = 'Welfare contribution recorded.';
      await load();
    });
  }

  async function submitClaim() {
    if (!session.activeGroupId || !session.access) return;
    busy = true;
    error = '';
    try {
      await api(`/groups/${session.activeGroupId}/welfare/claims`, {
        method: 'POST', auth: session.access,
        body: { amount, reason },
      });
      modal = null;
      notice = 'Claim sent to the committee.';
      await load();
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not submit the claim.';
    } finally {
      busy = false;
    }
  }

  async function decideClaim() {
    if (!session.activeGroupId || !session.access || !targetClaim) return;
    busy = true;
    error = '';
    try {
      await api(`/groups/${session.activeGroupId}/welfare/claims/${targetClaim.id}/decision`, {
        method: 'POST', auth: session.access,
        body: { decision, ...(comment.trim() ? { comment: comment.trim() } : {}) },
      });
      modal = null;
      notice = `Claim ${decision}.`;
      await load();
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not record the decision.';
    } finally {
      busy = false;
    }
  }

  function payClaim() {
    if (!session.activeGroupId || !session.access || !targetClaim) return;
    pinThen('Record welfare payout', 'This posts the approved claim to the welfare ledger.', async (token) => {
      await api(`/groups/${session.activeGroupId}/welfare/claims/${targetClaim?.id}/payout`, {
        method: 'POST', auth: session.access,
        headers: { 'X-Step-Up-Token': token, 'Idempotency-Key': crypto.randomUUID() },
        body: { channel, ...(reference.trim() ? { reference: reference.trim() } : {}) },
      });
      modal = null;
      notice = 'Welfare payout recorded.';
      await load();
    });
  }

  function memberName(id: string): string {
    return members.find((member) => member.user_id === id)?.display_name ?? 'Member';
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Member care</p><h1>Welfare</h1><p>A separate fund for the moments that matter. Every shilling remains on the chama's own shortcode.</p></div>
  <div class="page-actions">
    {#if manager}<ExportButtons reportCode="welfare_contributions" />{/if}
    {#if manager}<button class="btn btn-secondary" type="button" onclick={openSetup}><Icon name="settings" size={16} /> Fund settings</button>{/if}
  </div>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

{#if loading && !fund}
  <div class="skeleton-grid"><div class="skeleton skeleton-hero"></div><div class="skeleton"></div><div class="skeleton"></div></div>
{:else}
  {#if !fund?.configured}
    <section class="empty-state-card">
      <span class="empty-icon"><Icon name="welfare" size={28} /></span>
      <h2>No welfare fund yet</h2>
      <p>{manager ? 'Set the monthly contribution and activate the fund so members can contribute.' : 'The committee has not set up the welfare fund yet.'}</p>
      {#if manager}<button class="btn btn-primary" type="button" onclick={openSetup}>Set up the fund</button>{/if}
    </section>
  {:else}
    <section class="welfare-hero">
      <div>
        <span class="hero-label">{fund.name} <span class="live-dot"></span></span>
        <div class="hero-amount">{money(fund.balance, group?.currency)}</div>
        <p>Available to support approved claims</p>
        <div class="hero-actions">
          {#if manager}<button class="hero-button" type="button" onclick={openContribution}>Record contribution</button>{/if}
          <button class="hero-link" type="button" onclick={openClaim}>Request support <Icon name="chevron" size={14} /></button>
        </div>
      </div>
      <div class="welfare-stats">
        <div><span>Contributed</span><strong>{money(fund.contributed_total, group?.currency)}</strong></div>
        <div><span>Paid out</span><strong>{money(fund.paid_out_total, group?.currency)}</strong></div>
        <div><span>Monthly target</span><strong>{money(fund.monthly_amount, group?.currency)}</strong></div>
        <div><span>Status</span><strong class="capitalize">{fund.is_active ? 'Active' : 'Paused'}</strong></div>
      </div>
    </section>

    <div class="tab-bar">
      <button class="tab" class:active={tab === 'overview'} type="button" onclick={() => (tab = 'overview')}>Overview</button>
      <button class="tab" class:active={tab === 'contributions'} type="button" onclick={() => (tab = 'contributions')}>Contributions <span>{contributions.length}</span></button>
      <button class="tab" class:active={tab === 'claims'} type="button" onclick={() => (tab = 'claims')}>Claims <span>{pendingClaims.length}</span></button>
    </div>

    {#if tab === 'overview'}
      <div class="split-grid">
        <section class="card pad">
          <div class="card-head"><div><h2>Fund health</h2><p>What has come in and what has gone out.</p></div><span class="status-pill {fund.is_active ? 'green' : 'grey'}"><i></i>{fund.is_active ? 'Active' : 'Paused'}</span></div>
          <div class="metric-bars">
            <div><span><strong>Contributions</strong><small>{money(fund.contributed_total, group?.currency)}</small></span><div class="progress"><i style={`width:${Math.min(100, (Number(fund.contributed_total) / Math.max(1, Number(fund.contributed_total) + Number(fund.paid_out_total))) * 100)}%`}></i></div></div>
            <div><span><strong>Claims paid</strong><small>{money(fund.paid_out_total, group?.currency)}</small></span><div class="progress amber"><i style={`width:${Math.min(100, (Number(fund.paid_out_total) / Math.max(1, Number(fund.contributed_total) + Number(fund.paid_out_total))) * 100)}%`}></i></div></div>
          </div>
          <p class="footnote">Welfare is separate from savings. A claim can only be paid after approval and a PIN check.</p>
        </section>
        <section class="card pad">
          <div class="card-head"><div><h2>Committee queue</h2><p>{pendingClaims.length} pending · {approvedClaims.length} approved for payout.</p></div><Icon name="welfare" size={20} /></div>
          {#if pendingClaims.length === 0}
            <div class="empty compact"><p>No claims waiting for a decision.</p></div>
          {:else}
            {#each pendingClaims.slice(0, 3) as claim (claim.id)}
              <div class="queue-row"><span class="avatar avatar-sm">{initials(claim.member)}</span><div><strong>{claim.member}</strong><small>{money(claim.amount, group?.currency)} · {dateShort(claim.requested_at)}</small></div><span class="status-pill amber"><i></i>Pending</span></div>
            {/each}
            <button class="btn btn-secondary full-width" type="button" onclick={() => (tab = 'claims')}>Review claims</button>
          {/if}
        </section>
      </div>
      <div class="quick-grid">
        <button class="quick-tile" type="button" onclick={openContribution} disabled={!manager}><span class="quick-icon purple"><Icon name="plus" size={20} /></span><strong>Contribution</strong><small>Record a payment</small></button>
        <button class="quick-tile" type="button" onclick={openClaim}><span class="quick-icon green"><Icon name="welfare" size={20} /></span><strong>Request support</strong><small>Send to committee</small></button>
        <button class="quick-tile" type="button" onclick={() => (tab = 'claims')}><span class="quick-icon amber"><Icon name="fines" size={20} /></span><strong>Claims</strong><small>{pendingClaims.length} pending</small></button>
        <button class="quick-tile" type="button" onclick={openSetup} disabled={!manager}><span class="quick-icon pink"><Icon name="settings" size={20} /></span><strong>Settings</strong><small>Monthly target</small></button>
      </div>
    {:else if tab === 'contributions'}
      <section class="card table-card">
        <div class="card-head"><div><h2>Welfare contributions</h2><p>One contribution per member, per period.</p></div><div class="card-tools">{#if manager}<button class="btn btn-primary btn-small" type="button" onclick={openContribution}><Icon name="plus" size={15} /> Record</button><ExportButtons reportCode="welfare_contributions" compact />{/if}</div></div>
        {#if contributions.length === 0}
          <div class="empty"><span class="empty-icon"><Icon name="welfare" size={24} /></span><h3>No welfare contributions yet</h3><p>Record the first one to start the fund.</p></div>
        {:else}
          <div class="table-wrap"><table><thead><tr><th>Member</th><th>Period</th><th>Amount</th><th>Recorded</th><th>Ledger reference</th></tr></thead><tbody>
            {#each contributions as row (row.id)}
              <tr><td><span class="person"><span class="avatar avatar-sm">{initials(row.member)}</span>{row.member}</span></td><td class="mono">{row.period_label}</td><td class="money-cell">{money(row.amount, group?.currency)}</td><td class="muted small">{dateTime(row.created_at)}</td><td class="muted small mono">{row.transaction_id ? row.transaction_id.slice(0, 8) : '—'}</td></tr>
            {/each}
          </tbody></table></div>
        {/if}
      </section>
    {:else}
      <section class="card table-card">
        <div class="card-head"><div><h2>Claims</h2><p>{manager ? 'Review requests and record approved payouts.' : 'Your requests and their decisions.'}</p></div><div class="card-tools"><button class="btn btn-primary btn-small" type="button" onclick={openClaim}><Icon name="plus" size={15} /> Request support</button>{#if manager}<ExportButtons reportCode="welfare_claims" compact />{/if}</div></div>
        {#if claims.length === 0}
          <div class="empty"><span class="empty-icon"><Icon name="welfare" size={24} /></span><h3>No claims yet</h3><p>A claim starts here when a member needs support.</p></div>
        {:else}
          <div class="table-wrap"><table><thead><tr><th>Member</th><th>Reason</th><th>Amount</th><th>Status</th><th>Requested</th>{#if manager}<th>Action</th>{/if}</tr></thead><tbody>
            {#each claims as claim (claim.id)}
              <tr>
                <td><span class="person"><span class="avatar avatar-sm">{initials(claim.member)}</span>{claim.member}</span></td>
                <td><strong>{claim.reason}</strong>{#if claim.comment}<div class="muted small">{claim.comment}</div>{/if}</td>
                <td class="money-cell">{money(claim.amount, group?.currency)}</td>
                <td><span class="status-pill {tone(claim.status)}"><i></i>{titleCase(claim.status)}</span></td>
                <td class="muted small">{dateShort(claim.requested_at)}</td>
                {#if manager}
                  <td class="align-right">
                    {#if claim.status === 'pending'}<button class="btn btn-small btn-secondary" type="button" onclick={() => openDecision(claim)}>Review</button>{/if}
                    {#if claim.status === 'approved'}<button class="btn btn-small btn-green" type="button" onclick={() => openPayout(claim)}>Pay claim</button>{/if}
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody></table></div>
        {/if}
      </section>
    {/if}
  {/if}
{/if}

{#if modal === 'setup'}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) modal = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Welfare fund settings">
      <div class="modal-head"><div><h2>Welfare fund settings</h2><p>Set a clear monthly target for the group.</p></div><button class="icon-btn" type="button" onclick={() => (modal = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void saveFund(); }}>
        <div><label for="w-name">Fund name</label><input id="w-name" bind:value={fundName} maxlength="80" /></div>
        <div><label for="w-monthly">Monthly amount (KES)</label><input id="w-monthly" bind:value={monthly} inputmode="decimal" /></div>
        <label class="check-row"><input type="checkbox" bind:checked={active} /><span><strong>Active</strong><small>Members can contribute and request support.</small></span></label>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (modal = null)}>Cancel</button><button class="btn btn-primary" type="submit" disabled={busy}>{busy ? 'Saving…' : 'Save fund'}</button></div>
      </form>
    </div>
  </div>
{:else if modal === 'contribution'}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) modal = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Record welfare contribution">
      <div class="modal-head"><div><h2>Record a contribution</h2><p>This posts a completed entry to the welfare ledger.</p></div><button class="icon-btn" type="button" onclick={() => (modal = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); submitContribution(); }}>
        <div><label for="w-member">Member</label><select id="w-member" bind:value={memberID}>{#each members as member (member.user_id)}<option value={member.user_id}>{member.display_name}</option>{/each}</select></div>
        <div class="form-grid"><div><label for="w-amount">Amount (KES)</label><input id="w-amount" bind:value={amount} inputmode="decimal" /></div><div><label for="w-period">Period</label><input id="w-period" bind:value={period} placeholder="2026-11" /></div></div>
        <div><label for="w-channel">Channel</label><select id="w-channel" bind:value={channel}><option value="mpesa_manual">M-Pesa manual</option><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="other">Other</option></select></div>
        <div><label for="w-ref">Reference (optional)</label><input id="w-ref" bind:value={reference} placeholder="M-Pesa receipt" /></div>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (modal = null)}>Cancel</button><button class="btn btn-green" type="submit" disabled={!amount}>Continue</button></div>
      </form>
    </div>
  </div>
{:else if modal === 'claim'}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) modal = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Request welfare support">
      <div class="modal-head"><div><h2>Request support</h2><p>The committee will review your request.</p></div><button class="icon-btn" type="button" onclick={() => (modal = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void submitClaim(); }}>
        <div><label for="w-claim-amount">Amount (KES)</label><input id="w-claim-amount" bind:value={amount} inputmode="decimal" /></div>
        <div><label for="w-reason">What is this for?</label><textarea id="w-reason" bind:value={reason} rows="3" maxlength="300" placeholder="Explain the need briefly"></textarea></div>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (modal = null)}>Cancel</button><button class="btn btn-primary" type="submit" disabled={busy || !amount || !reason.trim()}>{busy ? 'Sending…' : 'Send request'}</button></div>
      </form>
    </div>
  </div>
{:else if modal === 'decision' && targetClaim}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) modal = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Review welfare claim">
      <div class="modal-head"><div><h2>Review claim</h2><p>{targetClaim.member} · {money(targetClaim.amount, group?.currency)}</p></div><button class="icon-btn" type="button" onclick={() => (modal = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <p class="muted small" style="margin-bottom: 1rem">{targetClaim.reason}</p>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void decideClaim(); }}>
        <div><label for="w-decision">Decision</label><select id="w-decision" bind:value={decision}><option value="approved">Approve</option><option value="rejected">Reject</option></select></div>
        <div><label for="w-comment">Comment (optional)</label><textarea id="w-comment" bind:value={comment} rows="2" maxlength="300"></textarea></div>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (modal = null)}>Cancel</button><button class="btn btn-primary" type="submit" disabled={busy}>{busy ? 'Saving…' : 'Record decision'}</button></div>
      </form>
    </div>
  </div>
{:else if modal === 'payout' && targetClaim}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) modal = null; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Record welfare payout">
      <div class="modal-head"><div><h2>Pay approved claim</h2><p>{targetClaim.member} · {money(targetClaim.amount, group?.currency)}</p></div><button class="icon-btn" type="button" onclick={() => (modal = null)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); payClaim(); }}>
        <div><label for="w-pay-channel">Channel</label><select id="w-pay-channel" bind:value={channel}><option value="mpesa_manual">M-Pesa manual</option><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="other">Other</option></select></div>
        <div><label for="w-pay-ref">Reference (optional)</label><input id="w-pay-ref" bind:value={reference} placeholder="M-Pesa receipt or voucher" /></div>
        <p class="secure-line"><Icon name="check" size={14} /> A PIN is required to record this payout.</p>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (modal = null)}>Cancel</button><button class="btn btn-green" type="submit">Continue</button></div>
      </form>
    </div>
  </div>
{/if}

{#if pinOpen}
  <PinModal
    title={pinTitle}
    subtitle={pinSubtitle}
    confirmLabel="Confirm welfare entry"
    onclose={() => (pinOpen = false)}
    onconfirm={async (token) => { if (pinAction) await pinAction(token); }}
  />
{/if}
