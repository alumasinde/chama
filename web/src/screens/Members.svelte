<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, isAdmin, session } from '../lib/session.svelte';
  import { dateShort, initials, titleCase, tone } from '../lib/format';
  import { inviteLink } from '../lib/invite';
  import type { Member } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';

  let members = $state<Member[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');
  let copied = $state(false);

  const group = $derived(activeGroup());
  const canExport = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  const pending = $derived(members.filter((member) => member.status === 'pending'));
  const activeCount = $derived(members.filter((member) => member.status === 'active').length);

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const result = await api<{ data: Member[] }>(`/groups/${session.activeGroupId}/members`, { auth: session.access });
      members = result.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load members.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  async function update(member: Member, body: { role?: string; status?: string }) {
    if (!session.activeGroupId || !session.access) return;
    error = '';
    notice = '';
    try {
      const updated = await api<Member>(`/groups/${session.activeGroupId}/members/${member.user_id}`, {
        method: 'PATCH', auth: session.access, body,
      });
      members = members.map((row) => (row.user_id === updated.user_id ? updated : row));
      notice = `${updated.display_name} updated. The change is in the audit trail.`;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not update that member.';
    }
  }

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
</script>

<div class="page-head">
  <div><p class="page-kicker">People</p><h1>Members</h1><p>{activeCount} active · {pending.length} waiting for approval in {group?.name}.</p></div>
  <div class="page-actions">{#if canExport}<ExportButtons reportCode="members" />{/if}<button class="btn btn-secondary" type="button" onclick={() => void load()}><Icon name="refresh" size={16} /> Refresh</button></div>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

<section class="invite-banner">
  <div><span class="kpi-icon purple"><Icon name="members" size={21} /></span><div><strong>Invite code</strong><small>Share this with someone you trust. An admin still approves them.</small></div></div>
  <div class="invite-banner-code"><code>{group?.invite_code}</code><button class="btn btn-secondary" type="button" onclick={copyInvite}>{copied ? 'Copied' : 'Copy link'}</button></div>
</section>

{#if isAdmin() && pending.length > 0}
  <section class="card pad approval-card">
    <div class="card-head"><div><h2>Waiting for approval</h2><p>New members cannot see group data until they are approved.</p></div><span class="count-badge">{pending.length}</span></div>
    <div class="approval-list">
      {#each pending as member (member.user_id)}
        <div class="approval-row">
          <span class="avatar">{initials(member.display_name)}</span>
          <div><strong>{member.display_name}</strong><small>Requested {dateShort(member.joined_at)}</small></div>
          <span class="spacer"></span>
          <button class="btn btn-small btn-green" type="button" onclick={() => void update(member, { status: 'active' })}>Approve</button>
          <button class="btn btn-small btn-danger" type="button" onclick={() => void update(member, { status: 'exited' })}>Decline</button>
        </div>
      {/each}
    </div>
  </section>
{/if}

<section class="card table-card">
  <div class="card-head"><div><h2>Member directory</h2><p>Roles control what each person can do.</p></div><span class="status-pill purple"><i></i>{members.length} total</span></div>
  {#if loading}
    <div class="skeleton-rows">{[1,2,3,4].map(() => '<div class="skeleton"></div>')}</div>
  {:else if members.length === 0}
    <div class="empty"><span class="empty-icon"><Icon name="members" size={24} /></span><h3>No members yet</h3><p>Share the invite code above.</p></div>
  {:else}
    <div class="table-wrap">
      <table>
        <thead><tr><th>Member</th><th>Role</th><th>Status</th><th>Joined</th>{#if isAdmin()}<th>Actions</th>{/if}</tr></thead>
        <tbody>
          {#each members as member (member.user_id)}
            <tr>
              <td><span class="person"><span class="avatar">{initials(member.display_name)}</span><span><strong>{member.display_name}</strong>{#if member.user_id === session.user?.id}<small class="muted">You</small>{/if}</span></span></td>
              <td>
                {#if isAdmin() && member.role !== 'admin'}
                  <select class="mini-select" value={member.role} aria-label="Role for {member.display_name}" onchange={(event) => void update(member, { role: (event.currentTarget as HTMLSelectElement).value })}>
                    <option value="member">Member</option>
                    <option value="secretary">Secretary</option>
                    <option value="treasurer">Treasurer</option>
                    <option value="admin">Admin</option>
                  </select>
                {:else}
                  <span class="role-chip">{titleCase(member.role)}</span>
                {/if}
              </td>
              <td><span class="status-pill {tone(member.status)}"><i></i>{titleCase(member.status)}</span></td>
              <td class="muted small">{dateShort(member.joined_at)}</td>
              {#if isAdmin()}
                <td class="align-right">
                  {#if member.user_id !== session.user?.id}
                    {#if member.status === 'active'}
                      <button class="btn btn-small btn-ghost" type="button" onclick={() => void update(member, { status: 'suspended' })}>Suspend</button>
                    {:else if member.status === 'suspended'}
                      <button class="btn btn-small btn-ghost" type="button" onclick={() => void update(member, { status: 'active' })}>Reinstate</button>
                    {/if}
                  {/if}
                </td>
              {/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>

<p class="footnote">The last active admin cannot be demoted. Every role or status change is written to the audit trail with before and after values.</p>
