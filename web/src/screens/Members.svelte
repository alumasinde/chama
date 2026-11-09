<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, isAdmin, session } from '../lib/session.svelte';
  import type { Member } from '../lib/types';

  let members = $state<Member[]>([]);
  let loading = $state(true);
  let error = $state('');
  let notice = $state('');

  const group = $derived(activeGroup());
  const pending = $derived(members.filter((member) => member.status === 'pending'));

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const result = await api<{ data: Member[] }>(
        `/groups/${session.activeGroupId}/members`,
        { auth: session.access },
      );
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
      const updated = await api<Member>(
        `/groups/${session.activeGroupId}/members/${member.user_id}`,
        { method: 'PATCH', auth: session.access, body },
      );
      members = members.map((row) => (row.user_id === updated.user_id ? updated : row));
      notice = `${updated.display_name} updated.`;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not update that member.';
    }
  }
</script>

<div class="section-head">
  <div>
    <h1>Members</h1>
    <p class="muted small">Approve new members and keep roles current.</p>
  </div>
  <button class="btn btn-secondary" onclick={() => void load()}>Refresh</button>
</div>

{#if error}<p class="error">{error}</p>{/if}
{#if notice}<p class="notice">{notice}</p>{/if}

{#if isAdmin() && pending.length > 0}
  <div class="card" style="padding: 1.25rem">
    <h2 style="margin-bottom: 0.75rem">Waiting for approval ({pending.length})</h2>
    {#each pending as member (member.user_id)}
      <div style="display: flex; align-items: center; gap: 1rem; padding: 0.6rem 0; border-bottom: 1px solid var(--line)">
        <div class="person" style="flex: 1">
          <div class="avatar">{member.first_name.charAt(0)}{member.last_name.charAt(0)}</div>
          <div>
            <div style="font-weight: 600">{member.display_name}</div>
            <div class="muted small">Requested to join</div>
          </div>
        </div>
        <button class="btn btn-primary" onclick={() => void update(member, { status: 'active' })}>Approve</button>
        <button class="btn btn-danger" onclick={() => void update(member, { status: 'exited' })}>Decline</button>
      </div>
    {/each}
  </div>
{/if}

<div class="card">
  {#if loading}
    <div class="empty">Loading members…</div>
  {:else if members.length === 0}
    <div class="empty"><h3>No members yet</h3><p class="small">Share the invite code from the overview.</p></div>
  {:else}
    <table>
      <thead>
        <tr><th>Member</th><th>Role</th><th>Status</th><th>Joined</th>{#if isAdmin()}<th></th>{/if}</tr>
      </thead>
      <tbody>
        {#each members as member (member.user_id)}
          <tr>
            <td>
              <div class="person">
                <div class="avatar">{member.first_name.charAt(0)}{member.last_name.charAt(0)}</div>
                <div>
                  <div style="font-weight: 600">{member.display_name}</div>
                  {#if member.user_id === session.user?.id}<div class="muted small">You</div>{/if}
                </div>
              </div>
            </td>
            <td>
              {#if isAdmin() && member.role !== 'admin'}
                <select
                  value={member.role}
                  aria-label="Role for {member.display_name}"
                  onchange={(event) => void update(member, { role: (event.currentTarget as HTMLSelectElement).value })}
                >
                  <option value="member">Member</option>
                  <option value="secretary">Secretary</option>
                  <option value="treasurer">Treasurer</option>
                  <option value="admin">Admin</option>
                </select>
              {:else}
                <span style="text-transform: capitalize">{member.role}</span>
              {/if}
            </td>
            <td><span class="badge badge-{member.status}">{member.status}</span></td>
            <td class="muted small">
              {member.joined_at ? new Date(member.joined_at).toLocaleDateString('en-KE', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'}
            </td>
            {#if isAdmin()}
              <td style="text-align: right">
                {#if member.role !== 'admin' || member.user_id !== session.user?.id}
                  {#if member.status === 'suspended'}
                    <button class="btn btn-ghost" onclick={() => void update(member, { status: 'active' })}>Reinstate</button>
                  {:else if member.status === 'active'}
                    <button class="btn btn-ghost" onclick={() => void update(member, { status: 'suspended' })}>Suspend</button>
                  {/if}
                {/if}
              </td>
            {/if}
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</div>

<p class="muted small">
  Admins can change roles for {group?.name ?? 'this chama'}. The last active admin cannot be demoted.
</p>
