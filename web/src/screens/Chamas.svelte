<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, loadGroups, session } from '../lib/session.svelte';
  import { money, dateShort, titleCase, initials, tone } from '../lib/format';
  import { inviteLink } from '../lib/invite';
  import type { View } from '../lib/nav';
  import type { Member } from '../lib/types';
  import Icon from '../components/Icon.svelte';

  let { onnav, oncreate, onjoin }: { onnav: (view: View) => void; oncreate: () => void; onjoin: () => void } = $props();
  const group = $derived(activeGroup());
  let members = $state<Member[]>([]);
  let copied = $state(false);
  let error = $state('');

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    try {
      const result = await api<{ data: Member[] }>(`/groups/${session.activeGroupId}/members`, { auth: session.access });
      members = result.data.filter((row) => row.status === 'active');
      error = '';
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load members.';
    }
  }

  $effect(() => {
    session.activeGroupId;
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

  async function switchGroup(id: string) {
    session.activeGroupId = id;
    await loadGroups();
    await load();
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Chama workspace</p><h1>{group?.name ?? 'My chama'}</h1><p>{group?.description || 'Your group ledger, members and money in one place.'}</p></div>
  <div class="page-actions">
    <button class="btn btn-secondary" type="button" onclick={onjoin}><Icon name="members" size={17} /> Join a chama</button>
    <button class="btn btn-secondary" type="button" onclick={oncreate}><Icon name="plus" size={17} /> New chama</button>
    <button class="btn btn-primary" type="button" onclick={() => onnav('members')}><Icon name="members" size={17} /> Members</button>
  </div>
</div>

{#if error}<p class="error">{error}</p>{/if}

{#if group}
  <section class="group-hero">
    <div class="group-hero-copy">
      <span class="status-pill on-purple"><i></i>{titleCase(group.status)}</span>
      <h2>{group.name}</h2>
      <p>{group.active_members} active members · you are {group.role}</p>
      <div class="avatar-stack">
        {#each members.slice(0, 6) as member (member.user_id)}
          <span class="avatar avatar-ring" title={member.display_name}>{initials(member.display_name)}</span>
        {/each}
        {#if group.active_members > 6}<span class="avatar avatar-ring avatar-more">+{group.active_members - 6}</span>{/if}
      </div>
    </div>
    <div class="group-hero-balance">
      <small>Group savings</small>
      <strong>{money(group.contribution_amount, group.currency)}</strong>
      <span>contribution · {titleCase(group.contribution_frequency)}</span>
    </div>
  </section>

  <div class="action-grid">
    <button class="action-tile" type="button" onclick={() => onnav('members')}><span class="kpi-icon purple"><Icon name="members" size={21} /></span><strong>Members</strong><small>{group.active_members} active</small><Icon name="chevron" size={16} /></button>
    <button class="action-tile" type="button" onclick={() => onnav('transactions')}><span class="kpi-icon green"><Icon name="transactions" size={21} /></span><strong>Contributions</strong><small>Ledger entries</small><Icon name="chevron" size={16} /></button>
    <button class="action-tile" type="button" onclick={() => onnav('loans')}><span class="kpi-icon amber"><Icon name="loans" size={21} /></span><strong>Loans</strong><small>Book and approvals</small><Icon name="chevron" size={16} /></button>
    <button class="action-tile" type="button" onclick={() => onnav('reports')}><span class="kpi-icon pink"><Icon name="reports" size={21} /></span><strong>Reports</strong><small>CSV and PDF</small><Icon name="chevron" size={16} /></button>
  </div>

  <div class="split-grid">
    <section class="card pad">
      <div class="card-head"><div><h2>Contribution terms</h2><p>Set when the chama was created.</p></div><span class="status-pill {tone(group.status)}"><i></i>{titleCase(group.status)}</span></div>
      <div class="detail-list">
        <div><span>Amount</span><strong>{money(group.contribution_amount, group.currency)}</strong></div>
        <div><span>Frequency</span><strong>{titleCase(group.contribution_frequency)}</strong></div>
        <div><span>Due day</span><strong>{group.contribution_day}</strong></div>
        <div><span>Grace period</span><strong>{group.late_grace_days} days</strong></div>
        <div><span>Created</span><strong>{dateShort(group.created_at)}</strong></div>
        <div><span>Your role</span><strong>{titleCase(group.role)}</strong></div>
      </div>
    </section>

    <section class="card pad">
      <div class="card-head"><div><h2>Invite your people</h2><p>They join as pending until an admin approves.</p></div><span class="kpi-icon purple"><Icon name="members" size={20} /></span></div>
      <div class="invite-code"><code>{group.invite_code}</code><button class="btn btn-secondary" type="button" onclick={copyInvite}>{copied ? 'Copied' : 'Copy link'}</button></div>
      <div class="trust-list">
        <span><Icon name="check" size={15} /> The code is unique to this chama</span>
        <span><Icon name="check" size={15} /> Admins approve every new member</span>
        <span><Icon name="check" size={15} /> No money is held by the platform</span>
      </div>
      <div class="inline-actions"><button class="btn btn-ghost" type="button" onclick={() => onnav('settings')}>M-Pesa shortcode</button><button class="btn btn-ghost" type="button" onclick={() => onnav('welfare')}>Welfare fund</button></div>
    </section>
  </div>

  <section class="card">
    <div class="card-head"><div><h2>All your chamas</h2><p>Switch the group used by the dashboard.</p></div><button class="btn btn-ghost" type="button" onclick={oncreate}><Icon name="plus" size={15} /> Create</button></div>
    <div class="group-list">
      {#each session.groups as item (item.id)}
        <button class="group-row" class:selected={item.id === session.activeGroupId} type="button" onclick={() => void switchGroup(item.id)}>
          <span class="avatar avatar-lg">{item.name.slice(0, 2).toUpperCase()}</span>
          <span class="group-row-copy"><strong>{item.name}</strong><small>{item.active_members} members · {titleCase(item.role)}</small></span>
          <span class="group-row-money">{money(item.contribution_amount, item.currency)}<small>{titleCase(item.contribution_frequency)}</small></span>
          <span class="status-pill {tone(item.status)}"><i></i>{titleCase(item.status)}</span>
          {#if item.id === session.activeGroupId}<Icon name="check" size={17} />{:else}<Icon name="chevron" size={17} />{/if}
        </button>
      {/each}
    </div>
  </section>
{:else}
  <div class="card empty"><h3>No chama selected</h3><p>Create a chama to begin.</p><button class="btn btn-primary" type="button" onclick={oncreate}>Create a chama</button></div>
{/if}
