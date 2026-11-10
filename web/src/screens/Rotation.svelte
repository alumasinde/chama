<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { money, dateShort, titleCase, tone, initials, percent } from '../lib/format';
  import type { Member, Proposal, ProposalSummary, RotationCycle, RotationSlot } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';
  import PinModal from '../components/PinModal.svelte';

  const group = $derived(activeGroup());
  const manager = $derived(['admin', 'treasurer'].includes(group?.role ?? ''));
  let cycles = $state<RotationCycle[]>([]);
  let selected = $state<RotationCycle | null>(null);
  let proposals = $state<ProposalSummary[]>([]);
  let proposal = $state<Proposal | null>(null);
  let members = $state<Member[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let createOpen = $state(false);
  let proposalOpen = $state(false);

  let name = $state('2026 rotation');
  let contribution = $state('1000.00');
  let startsOn = $state(new Date().toISOString().slice(0, 10));
  let mode = $state<'random' | 'manual' | 'vote'>('random');
  let manualOrder = $state<Member[]>([]);
  let quorum = $state(60);
  let closesAt = $state(defaultCloses());

  let pinOpen = $state(false);
  let pinTitle = $state('');
  let pinSubtitle = $state('');
  let pinAction: ((token: string) => Promise<void>) | null = $state(null);

  const mySlot = $derived(selected?.slots.find((slot) => slot.user_id === session.user?.id) ?? null);
  const nextSlot = $derived(selected?.slots.find((slot) => !slot.paid) ?? null);
  const paidPercent = $derived(selected ? percent(selected.paid_count, selected.slot_count) : 0);
  const activeProposal = $derived(proposals.find((row) => row.status === 'open') ?? null);

  function defaultCloses(): string {
    const date = new Date(Date.now() + 3 * 86400000);
    return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  }

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const [cycleResult, memberResult] = await Promise.all([
        api<{ data: RotationCycle[] }>(`/groups/${session.activeGroupId}/rotation/cycles`, { auth: session.access }),
        api<{ data: Member[] }>(`/groups/${session.activeGroupId}/members`, { auth: session.access }),
      ]);
      cycles = cycleResult.data;
      members = memberResult.data.filter((member) => member.status === 'active');
      if (manualOrder.length === 0) manualOrder = [...members];
      if (cycles.length > 0) {
        const target = selected && cycles.some((cycle) => cycle.id === selected?.id) ? selected.id : cycles[0].id;
        await selectCycle(target, false);
      } else {
        selected = null;
      }
      if (contribution === '1000.00' && group) contribution = group.contribution_amount;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load rotation cycles.';
    } finally {
      loading = false;
    }
  }

  async function selectCycle(id: string, clearError = true) {
    if (!session.activeGroupId || !session.access) return;
    if (clearError) error = '';
    try {
      const [cycle, proposalList] = await Promise.all([
        api<RotationCycle>(`/groups/${session.activeGroupId}/rotation/cycles/${id}`, { auth: session.access }),
        api<{ data: ProposalSummary[] }>(`/groups/${session.activeGroupId}/rotation/cycles/${id}/proposals`, { auth: session.access }),
      ]);
      selected = cycle;
      proposals = proposalList.data;
      proposal = null;
      const current = proposalList.data.find((row) => row.status === 'open') ?? proposalList.data[0];
      if (current) await loadProposal(current.id, false);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load that cycle.';
    }
  }

  async function loadProposal(id: string, clearError = true) {
    if (!session.activeGroupId || !session.access) return;
    if (clearError) error = '';
    try {
      proposal = await api<Proposal>(`/groups/${session.activeGroupId}/rotation/proposals/${id}`, { auth: session.access });
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load that proposal.';
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  function moveMember(index: number, delta: number) {
    const next = index + delta;
    if (next < 0 || next >= manualOrder.length) return;
    const copy = [...manualOrder];
    [copy[index], copy[next]] = [copy[next], copy[index]];
    manualOrder = copy;
  }

  async function createCycle() {
    if (!session.activeGroupId || !session.access) return;
    error = '';
    notice = '';
    try {
      const body: Record<string, unknown> = {
        name, ordering_mode: mode, contribution_amount: contribution, starts_on: startsOn,
      };
      if (mode === 'manual') body.slots = manualOrder.map((member) => member.user_id);
      const created = await api<RotationCycle>(`/groups/${session.activeGroupId}/rotation/cycles`, {
        method: 'POST', auth: session.access, body,
      });
      createOpen = false;
      selected = created;
      notice = mode === 'vote' ? 'Draft created. Propose the order for a vote.' : 'Cycle created. Start it when the group is ready.';
      await load();
      await selectCycle(created.id);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not create the cycle.';
    }
  }

  async function startCycle() {
    if (!session.activeGroupId || !session.access || !selected) return;
    error = '';
    try {
      await api(`/groups/${session.activeGroupId}/rotation/cycles/${selected.id}/start`, { method: 'POST', auth: session.access });
      notice = 'Rotation started. The queue is now live.';
      await selectCycle(selected.id);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not start the cycle.';
    }
  }

  async function createProposal() {
    if (!session.activeGroupId || !session.access || !selected) return;
    error = '';
    try {
      const created = await api<Proposal>(`/groups/${session.activeGroupId}/rotation/cycles/${selected.id}/proposals`, {
        method: 'POST', auth: session.access,
        body: {
          slots: manualOrder.map((member) => member.user_id),
          closes_at: new Date(closesAt).toISOString(),
          quorum_percent: Number(quorum),
        },
      });
      proposalOpen = false;
      proposal = created;
      notice = 'Proposal opened. Members can now vote.';
      await selectCycle(selected.id);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not open the proposal.';
    }
  }

  async function castVote(choice: string) {
    if (!session.activeGroupId || !session.access || !proposal) return;
    error = '';
    try {
      proposal = await api<Proposal>(`/groups/${session.activeGroupId}/rotation/proposals/${proposal.id}/vote`, {
        method: 'POST', auth: session.access, body: { choice },
      });
      notice = `Vote recorded: ${choice}.`;
      if (selected) await selectCycle(selected.id, false);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not record that vote.';
    }
  }

  async function closeProposal() {
    if (!session.activeGroupId || !session.access || !proposal) return;
    error = '';
    try {
      proposal = await api<Proposal>(`/groups/${session.activeGroupId}/rotation/proposals/${proposal.id}/close`, {
        method: 'POST', auth: session.access,
      });
      notice = 'Vote closed. The result is final.';
      if (selected) await selectCycle(selected.id, false);
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not close the proposal.';
    }
  }

  function payout(slot: RotationSlot) {
    if (!session.activeGroupId || !session.access || !selected) return;
    pinTitle = 'Record rotation payout';
    pinSubtitle = `${slot.member} receives ${money(selected.contribution_amount, group?.currency)} for turn ${slot.position}.`;
    pinAction = async (token) => {
      await api(`/groups/${session.activeGroupId}/rotation/cycles/${selected?.id}/payouts`, {
        method: 'POST', auth: session.access,
        headers: { 'X-Step-Up-Token': token, 'Idempotency-Key': crypto.randomUUID() },
        body: { slot_id: slot.id, channel: 'mpesa_manual' },
      });
      pinOpen = false;
      notice = `Payout recorded for ${slot.member}.`;
      if (selected) await selectCycle(selected.id, false);
    };
    pinOpen = true;
  }

  function canPay(slot: RotationSlot): boolean {
    return manager && selected?.status === 'active' && !slot.paid && nextSlot?.id === slot.id;
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Merry-go-round</p><h1>Rotation</h1><p>Agree the order, vote when needed, and record each turn without holding anyone's money.</p></div>
  <div class="page-actions">{#if manager}<ExportButtons reportCode="rotation" /><button class="btn btn-primary" type="button" onclick={() => (createOpen = true)}><Icon name="plus" size={17} /> New cycle</button>{/if}</div>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

{#if loading && cycles.length === 0}
  <div class="skeleton-grid"><div class="skeleton skeleton-hero"></div><div class="skeleton"></div><div class="skeleton"></div></div>
{:else if cycles.length === 0}
  <section class="empty-state-card">
    <span class="empty-icon"><Icon name="rotation" size={28} /></span>
    <h2>Start your first rotation</h2>
    <p>{manager ? 'A rotation needs at least two active members. Choose random draw, a manual order, or a member vote.' : 'The committee has not opened a rotation cycle yet. Your turn will appear here when it does.'}</p>
    {#if manager}<button class="btn btn-primary" type="button" onclick={() => (createOpen = true)}>Create a cycle</button>{/if}
  </section>
{:else}
  <div class="cycle-strip">
    {#each cycles as cycle (cycle.id)}
      <button class="cycle-chip" class:active={selected?.id === cycle.id} type="button" onclick={() => void selectCycle(cycle.id)}>
        <span class="status-dot {cycle.status === 'completed' ? 'green' : cycle.status === 'active' ? 'purple' : 'grey'}"></span>
        <span><strong>{cycle.name}</strong><small>{titleCase(cycle.ordering_mode)} · {cycle.paid_count}/{cycle.slot_count} paid</small></span>
      </button>
    {/each}
  </div>

  {#if selected}
    <section class="rotation-hero">
      <div>
        <div class="hero-label">{selected.name} <span class="status-pill on-purple"><i></i>{titleCase(selected.status)}</span></div>
        <div class="hero-amount">{money(selected.contribution_amount, group?.currency)}</div>
        <p>paid to each member on their turn</p>
        <div class="hero-actions">
          {#if manager && selected.status === 'draft' && selected.ordering_mode !== 'vote'}<button class="hero-button" type="button" onclick={() => void startCycle()}>Start rotation</button>{/if}
          {#if manager && selected.status === 'draft' && selected.ordering_mode === 'vote'}<button class="hero-button" type="button" onclick={() => (proposalOpen = true)}>Propose order</button>{/if}
          {#if manager && selected.status === 'active' && nextSlot}<button class="hero-button" type="button" onclick={() => payout(nextSlot)}>Pay next turn</button>{/if}
          {#if mySlot}<span class="hero-link">Your turn: {dateShort(mySlot.payout_date)} · position {mySlot.position}</span>{/if}
        </div>
      </div>
      <div class="rotation-progress">
        <div class="radial" style={`--progress:${paidPercent * 3.6}deg`}><span>{paidPercent}%</span></div>
        <div><strong>{selected.paid_count} of {selected.slot_count} turns paid</strong><small>{titleCase(selected.ordering_mode)} order · starts {dateShort(selected.starts_on)}</small></div>
      </div>
    </section>

    <div class="rotation-grid">
      <section class="card table-card">
        <div class="card-head"><div><h2>The queue</h2><p>Payouts move in position order.</p></div><span class="date-chip">{selected.member_count} members</span></div>
        {#if selected.slots.length === 0}
          <div class="empty"><span class="empty-icon"><Icon name="rotation" size={24} /></span><h3>Order not drawn yet</h3><p>{selected.ordering_mode === 'vote' ? 'Propose an order and let members vote.' : 'Start the cycle to draw the order.'}</p></div>
        {:else}
          <div class="table-wrap"><table><thead><tr><th>#</th><th>Member</th><th>Payout date</th><th>Status</th>{#if manager}<th></th>{/if}</tr></thead><tbody>
            {#each selected.slots as slot (slot.id)}
              <tr class:my-row={slot.user_id === session.user?.id}>
                <td><span class="position-dot">{slot.position}</span></td>
                <td><span class="person"><span class="avatar avatar-sm">{initials(slot.member)}</span><span>{slot.member}{#if slot.user_id === session.user?.id}<small class="muted">You</small>{/if}</span></span></td>
                <td>{dateShort(slot.payout_date)}</td>
                <td><span class="status-pill {slot.paid ? 'green' : 'amber'}"><i></i>{slot.paid ? 'Paid' : 'Waiting'}</span></td>
                {#if manager}<td class="align-right">{#if !slot.paid}<button class="btn btn-small" class:btn-green={canPay(slot)} class:btn-secondary={!canPay(slot)} type="button" disabled={!canPay(slot)} onclick={() => payout(slot)}>{canPay(slot) ? 'Record payout' : 'Not next'}</button>{/if}</td>{/if}
              </tr>
            {/each}
          </tbody></table></div>
        {/if}
      </section>

      <section class="card proposal-card">
        <div class="card-head"><div><h2>Order vote</h2><p>{activeProposal ? 'The proposed order is open for votes.' : proposals.length ? 'Latest proposal result.' : 'No proposal yet.'}</p></div>{#if manager && selected.ordering_mode === 'vote' && selected.status === 'draft'}<button class="btn btn-small btn-secondary" type="button" onclick={() => (proposalOpen = true)}>New proposal</button>{/if}</div>
        {#if proposal}
          <div class="proposal-top">
            <span class="status-pill {tone(proposal.status)}"><i></i>{titleCase(proposal.status)}</span>
            <span class="muted small">Closes {dateShort(proposal.closes_at)}</span>
          </div>
          <div class="tally">
            <div><strong>{proposal.for}</strong><span>For</span></div>
            <div><strong>{proposal.against}</strong><span>Against</span></div>
            <div><strong>{proposal.abstain}</strong><span>Abstain</span></div>
            <div><strong>{proposal.needed}</strong><span>Needed</span></div>
          </div>
          <div class="progress"><i style={`width:${percent(proposal.total, proposal.eligible_members)}%`}></i></div>
          <p class="muted small">{proposal.total} of {proposal.eligible_members} members voted. At least {proposal.needed} need to vote for a decision.</p>
          {#if proposal.status === 'open'}
            <div class="vote-actions">
              <button class="btn btn-green" type="button" onclick={() => void castVote('for')}>{proposal.my_vote?.choice === 'for' ? 'Voted yes' : 'Vote yes'}</button>
              <button class="btn btn-secondary" type="button" onclick={() => void castVote('against')}>Vote no</button>
              <button class="btn btn-ghost" type="button" onclick={() => void castVote('abstain')}>Abstain</button>
            </div>
            {#if manager}<button class="btn btn-secondary full-width" type="button" onclick={() => void closeProposal()}>Close vote now</button>{/if}
          {:else if proposal.result}
            <p class="notice">{proposal.result.for > proposal.result.against ? 'Order approved.' : 'Order not approved.'} {proposal.result.for} for, {proposal.result.against} against.</p>
          {/if}
          <div class="proposal-order">
            {#each proposal.slots as slot (slot.id)}<span><i>{slot.position}</i>{slot.member}</span>{/each}
          </div>
        {:else}
          <div class="empty compact"><p>{selected.ordering_mode === 'vote' ? 'Create a proposal to start the vote.' : 'This cycle did not use a vote.'}</p></div>
        {/if}
        {#if proposals.length > 0}
          <div class="past-proposals">
            {#each proposals as item (item.id)}<button type="button" class="past-proposal" onclick={() => void loadProposal(item.id)}><span>{dateShort(item.created_at)}</span><span class="status-pill {tone(item.status)}"><i></i>{titleCase(item.status)}</span><Icon name="chevron" size={14} /></button>{/each}
          </div>
        {/if}
      </section>
    </div>
  {/if}
{/if}

{#if createOpen}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) createOpen = false; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Create rotation cycle">
      <div class="modal-head"><div><h2>Create a rotation</h2><p>Set the payout amount and how the order is decided.</p></div><button class="icon-btn" type="button" onclick={() => (createOpen = false)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void createCycle(); }}>
        <div><label for="r-name">Cycle name</label><input id="r-name" bind:value={name} maxlength="80" /></div>
        <div class="form-grid"><div><label for="r-amount">Payout per member (KES)</label><input id="r-amount" bind:value={contribution} inputmode="decimal" /></div><div><label for="r-start">Starts on</label><input id="r-start" type="date" bind:value={startsOn} /></div></div>
        <div><span class="field-label">Ordering</span><div class="segmented full"><button type="button" class:active={mode === 'random'} onclick={() => (mode = 'random')}>Random</button><button type="button" class:active={mode === 'manual'} onclick={() => (mode = 'manual')}>Manual</button><button type="button" class:active={mode === 'vote'} onclick={() => (mode = 'vote')}>Vote</button></div></div>
        {#if mode !== 'random'}
          <div class="order-editor">
            <div class="order-editor-head"><strong>Proposed order</strong><small>Use the arrows to arrange every active member.</small></div>
            {#each manualOrder as member, index (member.user_id)}
              <div class="order-row"><span class="position-dot">{index + 1}</span><span class="avatar avatar-sm">{initials(member.display_name)}</span><span class="order-name">{member.display_name}</span><button class="icon-btn" type="button" onclick={() => moveMember(index, -1)} aria-label="Move up">↑</button><button class="icon-btn" type="button" onclick={() => moveMember(index, 1)} aria-label="Move down">↓</button></div>
            {/each}
          </div>
        {/if}
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (createOpen = false)}>Cancel</button><button class="btn btn-primary" type="submit" disabled={!name || !contribution}>{mode === 'vote' ? 'Create draft' : 'Create cycle'}</button></div>
      </form>
    </div>
  </div>
{/if}

{#if proposalOpen && selected}
  <div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) proposalOpen = false; }}>
    <div class="modal" role="dialog" aria-modal="true" aria-label="Propose rotation order">
      <div class="modal-head"><div><h2>Propose an order</h2><p>Members will vote on this exact queue.</p></div><button class="icon-btn" type="button" onclick={() => (proposalOpen = false)} aria-label="Close"><Icon name="close" size={18} /></button></div>
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void createProposal(); }}>
        <div class="form-grid"><div><label for="r-close">Voting closes</label><input id="r-close" type="datetime-local" bind:value={closesAt} /></div><div><label for="r-quorum">Quorum (%)</label><input id="r-quorum" type="number" min="1" max="100" bind:value={quorum} /></div></div>
        <div class="proposal-order compact-order">{#each manualOrder as member, index (member.user_id)}<span><i>{index + 1}</i>{member.display_name}</span>{/each}</div>
        <p class="footnote">At least {Math.ceil((manualOrder.length * Number(quorum)) / 100)} of {manualOrder.length} members must vote.</p>
        <div class="modal-actions"><button class="btn btn-secondary" type="button" onclick={() => (proposalOpen = false)}>Cancel</button><button class="btn btn-primary" type="submit">Open vote</button></div>
      </form>
    </div>
  </div>
{/if}

{#if pinOpen}
  <PinModal title={pinTitle} subtitle={pinSubtitle} confirmLabel="Record payout" onclose={() => (pinOpen = false)} onconfirm={async (token) => { if (pinAction) await pinAction(token); }} />
{/if}
