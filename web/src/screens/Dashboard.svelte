<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import type { Transaction } from '../lib/types';
  import PayIn from './PayIn.svelte';

  let { onnav }: { onnav: (view: 'members' | 'payments') => void } = $props();
  const group = $derived(activeGroup());
  let copied = $state(false);
  let paying = $state(false);
  let activity = $state<Transaction[]>([]);
  let activityLoading = $state(true);
  let activityError = $state('');

  async function loadActivity() {
    if (!session.activeGroupId || !session.access) return;
    activityLoading = true;
    try {
      const result = await api<{ data: Transaction[] }>(
        `/groups/${session.activeGroupId}/transactions?limit=8`,
        { auth: session.access },
      );
      activity = result.data;
      activityError = '';
    } catch (err) {
      activityError = err instanceof ApiFailure ? err.message : 'Could not load recent activity.';
    } finally {
      activityLoading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void loadActivity();
  });

  async function copyInvite() {
    if (!group) return;
    try {
      await navigator.clipboard.writeText(group.invite_code);
      copied = true;
      setTimeout(() => (copied = false), 1600);
    } catch {
      copied = false;
    }
  }
</script>

{#if group}
  <div class="section-head">
    <div>
      <h1>{group.name}</h1>
      <p class="muted small">
        {group.active_members} active {group.active_members === 1 ? 'member' : 'members'} · you are {group.role}
      </p>
    </div>
    <span class="badge badge-{group.status}">{group.status}</span>
  </div>

  <div class="balance">
    <span class="label">Contribution · {group.contribution_frequency}</span>
    <span class="amount">{group.currency} {group.contribution_amount}</span>
    <span class="meta">
      Due on day {group.contribution_day} · {group.late_grace_days} day grace before a late fine
    </span>
  </div>

  <div class="quick">
    <button onclick={() => onnav('members')}><span class="icon">👥</span> Members</button>
    <button onclick={() => onnav('payments')}><span class="icon">📲</span> M-Pesa setup</button>
    <button onclick={copyInvite}><span class="icon">🔗</span> {copied ? 'Copied' : 'Copy invite'}</button>
    <button onclick={() => (paying = true)}><span class="icon">💸</span> Pay in</button>
  </div>

  <div class="grid-2">
    <div class="card" style="padding: 1.25rem">
      <h2 style="margin-bottom: 0.75rem">Invite members</h2>
      <p class="muted small" style="margin-bottom: 1rem">
        Share this code. New members wait for an admin approval before they can see group data.
      </p>
      <div class="invite">
        <code>{group.invite_code}</code>
        <button class="btn btn-secondary" onclick={copyInvite}>{copied ? 'Copied' : 'Copy'}</button>
      </div>
    </div>
    <div class="card" style="padding: 1.25rem">
      <h2 style="margin-bottom: 0.75rem">Your access</h2>
      <div class="grid-2">
        <div class="stat" style="padding: 0.5rem 0">
          <span class="muted small">Role</span>
          <span class="value" style="font-size: 1.1rem; text-transform: capitalize">{group.role}</span>
        </div>
        <div class="stat" style="padding: 0.5rem 0">
          <span class="muted small">Frequency</span>
          <span class="value" style="font-size: 1.1rem; text-transform: capitalize">{group.contribution_frequency}</span>
        </div>
        <div class="stat" style="padding: 0.5rem 0">
          <span class="muted small">Invite code</span>
          <span class="value" style="font-size: 1.1rem">{group.invite_code}</span>
        </div>
        <div class="stat" style="padding: 0.5rem 0">
          <span class="muted small">Account</span>
          <span class="value" style="font-size: 1.1rem">{session.user?.first_name}</span>
        </div>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="section-head" style="padding: 1.25rem 1.25rem 0.5rem">
      <div>
        <h2>Recent activity</h2>
        <p class="muted small">Payments recorded against {group.name}.</p>
      </div>
      <button class="btn btn-ghost" onclick={() => void loadActivity()}>Refresh</button>
    </div>
    {#if activityLoading}
      <div class="empty">Loading activity…</div>
    {:else if activityError}
      <p class="error" style="margin: 0 1.25rem 1.25rem">{activityError}</p>
    {:else if activity.length === 0}
      <div class="empty">
        <h3>Nothing recorded yet</h3>
        <p class="small">Use Pay in to make the first contribution.</p>
      </div>
    {:else}
      <table>
        <thead>
          <tr><th>When</th><th>Member</th><th>Purpose</th><th>Amount</th><th>Status</th><th>Receipt</th></tr>
        </thead>
        <tbody>
          {#each activity as entry (entry.id)}
            <tr>
              <td class="muted small">
                {new Date(entry.created_at).toLocaleString('en-KE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
              </td>
              <td>{entry.member}</td>
              <td style="text-transform: capitalize">{entry.type.replace('_', ' ')}</td>
              <td style="font-weight: 650">{group.currency} {entry.amount}</td>
              <td><span class="badge badge-{entry.status}">{entry.status}</span></td>
              <td class="muted small">{entry.reference_code ?? '—'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </div>

  {#if group.description}
    <div class="card" style="padding: 1.25rem">
      <h2 style="margin-bottom: 0.5rem">About this chama</h2>
      <p class="muted">{group.description}</p>
    </div>
  {/if}
{:else}
  <div class="card empty"><h3>Select a chama</h3></div>
{/if}

{#if paying}
  <PayIn onclose={() => { paying = false; void loadActivity(); }} />
{/if}
