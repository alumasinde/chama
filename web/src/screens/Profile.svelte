<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, loadGroups, session, signOut } from '../lib/session.svelte';
  import { dateShort, dateTime, titleCase, tone } from '../lib/format';
  import type { View } from '../lib/nav';
  import type { NotificationItem } from '../lib/types';
  import Icon from '../components/Icon.svelte';

  let { onnav }: { onnav: (view: View) => void } = $props();
  const group = $derived(activeGroup());
  let notifications = $state<NotificationItem[]>([]);
  let unread = $state(0);
  let error = $state('');

  async function loadNotifications() {
    if (!session.access) return;
    try {
      const result = await api<{ data: NotificationItem[]; unread_count: number }>('/notifications?limit=8', { auth: session.access });
      notifications = result.data;
      unread = result.unread_count;
    } catch {
      // Notifications are helpful but never block the profile.
    }
  }

  async function markRead() {
    if (!session.access) return;
    try {
      await api('/notifications/read', { method: 'POST', auth: session.access, body: { all: true } });
      unread = 0;
      notifications = notifications.map((item) => ({ ...item, read_at: item.read_at ?? new Date().toISOString() }));
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not mark notifications read.';
    }
  }

  async function switchGroup(id: string) {
    session.activeGroupId = id;
    await loadGroups();
    onnav('overview');
  }

  $effect(() => {
    session.access;
    void loadNotifications();
  });
</script>

<div class="page-head">
  <div><p class="page-kicker">Your account</p><h1>Profile</h1><p>Your details, memberships and recent notifications.</p></div>
  <div class="page-actions"><button class="btn btn-danger" type="button" onclick={() => signOut()}><Icon name="logout" size={17} /> Sign out</button></div>
</div>

{#if error}<p class="error">{error}</p>{/if}

<section class="profile-hero">
  <div class="profile-avatar">{session.user?.first_name?.charAt(0)}{session.user?.last_name?.charAt(0)}</div>
  <div><h2>{session.user?.display_name}</h2><p>{session.user?.phone_number} · <span class="status-pill green"><i></i>Verified</span></p><span class="muted small">Member since {group ? dateShort(group.created_at) : 'today'}</span></div>
  <div class="profile-actions"><button class="btn btn-secondary" type="button" onclick={() => onnav('settings')}><Icon name="settings" size={16} /> Group settings</button></div>
</section>

<div class="split-grid">
  <section class="card pad">
    <div class="card-head"><div><h2>Account</h2><p>Your sign-in identity.</p></div><span class="kpi-icon purple"><Icon name="profile" size={20} /></span></div>
    <div class="detail-list">
      <div><span>First name</span><strong>{session.user?.first_name}</strong></div>
      <div><span>Last name</span><strong>{session.user?.last_name}</strong></div>
      <div><span>Phone</span><strong>{session.user?.phone_number}</strong></div>
      <div><span>Email</span><strong>{session.user?.email ?? 'Not added'}</strong></div>
      <div><span>PIN</span><strong>{session.user?.pin_set ? 'Set' : 'Not set'}</strong></div>
      <div><span>Password</span><strong>{session.user?.has_password ? 'Set' : 'Not set'}</strong></div>
    </div>
    <p class="footnote">Your PIN authorises payments. The platform never sees your M-Pesa PIN.</p>
  </section>

  <section class="card pad">
    <div class="card-head"><div><h2>Notifications</h2><p>{unread ? `${unread} unread` : 'All caught up'}.</p></div>{#if unread}<button class="btn btn-small btn-ghost" type="button" onclick={() => void markRead()}>Mark read</button>{/if}</div>
    {#if notifications.length === 0}
      <div class="empty compact"><span class="empty-icon"><Icon name="bell" size={22} /></span><p>No notifications yet.</p></div>
    {:else}
      <div class="notification-list">
        {#each notifications as item (item.id)}
          <div class="notification-row" class:unread={!item.read_at}>
            <span class="notification-icon"><Icon name={item.type.includes('loan') ? 'loans' : item.type.includes('payment') ? 'transactions' : item.type.includes('fine') ? 'fines' : 'bell'} size={17} /></span>
            <div><strong>{item.title}</strong><p>{item.body}</p><small>{dateTime(item.created_at)}</small></div>
            {#if !item.read_at}<i class="unread-dot"></i>{/if}
          </div>
        {/each}
      </div>
    {/if}
  </section>
</div>

<section class="card">
  <div class="card-head"><div><h2>My chamas</h2><p>Switch the chama used across the dashboard.</p></div><button class="btn btn-ghost" type="button" onclick={() => onnav('chamas')}>Manage</button></div>
  <div class="group-list">
    {#each session.groups as item (item.id)}
      <button class="group-row" class:selected={item.id === session.activeGroupId} type="button" onclick={() => void switchGroup(item.id)}>
        <span class="avatar avatar-lg">{item.name.slice(0, 2).toUpperCase()}</span>
        <span class="group-row-copy"><strong>{item.name}</strong><small>{item.active_members} members · {titleCase(item.role)}</small></span>
        <span class="status-pill {tone(item.status)}"><i></i>{titleCase(item.status)}</span>
        {#if item.id === session.activeGroupId}<span class="status-pill purple"><i></i>Current</span>{:else}<Icon name="chevron" size={17} />{/if}
      </button>
    {/each}
  </div>
</section>

<section class="card pad">
  <div class="card-head"><div><h2>Help & trust</h2><p>What this platform does and does not do.</p></div><span class="kpi-icon green"><Icon name="check" size={20} /></span></div>
  <div class="trust-list">
    <span><Icon name="check" size={15} /> Every chama keeps its own M-Pesa shortcode.</span>
    <span><Icon name="check" size={15} /> The platform records the ledger; it does not hold money.</span>
    <span><Icon name="check" size={15} /> Exports and audit entries stay inside your chama.</span>
  </div>
</section>
