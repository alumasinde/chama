<script lang="ts">
  import { onMount } from 'svelte';
  import { session, loadGroups, signOut, isAdmin } from '../lib/session.svelte';
  import Dashboard from './Dashboard.svelte';
  import Members from './Members.svelte';
  import PaymentSettings from './PaymentSettings.svelte';
  import CreateGroup from './CreateGroup.svelte';

  let view = $state<'dashboard' | 'members' | 'payments'>('dashboard');
  let showCreate = $state(false);
  let error = $state('');

  onMount(async () => {
    try {
      await loadGroups();
    } catch {
      error = 'Could not load your chamas. Pull to refresh or sign in again.';
    }
  });

  async function created() {
    showCreate = false;
    await loadGroups();
    view = 'dashboard';
  }
</script>

<div class="shell">
  <aside class="sidebar">
    <div>
      <div class="brand">{session.appName}</div>
      <div class="brand-sub small" style="opacity: 0.7; padding: 0 0.5rem">Ledger, not a wallet</div>
    </div>
    <nav>
      <button class="nav-item" class:active={view === 'dashboard'} onclick={() => (view = 'dashboard')}>
        <span class="dot"></span> Overview
      </button>
      <button class="nav-item" class:active={view === 'members'} onclick={() => (view = 'members')}>
        <span class="dot"></span> Members
      </button>
      <button class="nav-item" class:active={view === 'payments'} onclick={() => (view = 'payments')}>
        <span class="dot"></span> M-Pesa settings
      </button>
    </nav>
    <div class="who">
      <div style="font-weight: 650">{session.user?.display_name}</div>
      <div style="opacity: 0.75">{session.user?.phone_number}</div>
      <button class="btn btn-ghost" style="color: var(--gold-500); padding-left: 0; margin-top: 0.35rem" onclick={() => signOut()}>
        Sign out
      </button>
    </div>
  </aside>

  <div class="main">
    <header class="topbar">
      {#if session.groups.length > 0}
        <div class="group-switch">
          <select bind:value={session.activeGroupId} aria-label="Active chama">
            {#each session.groups as group (group.id)}
              <option value={group.id}>{group.name}</option>
            {/each}
          </select>
        </div>
        {#if isAdmin()}
          <button class="btn btn-secondary" onclick={() => (showCreate = true)}>New chama</button>
        {/if}
      {:else}
        <strong>{session.appName}</strong>
      {/if}
      <span style="flex: 1"></span>
      <span class="muted small">Platform records only — money moves on your chama's shortcode.</span>
    </header>

    <section class="content">
      {#if error}<p class="error">{error}</p>{/if}
      {#if session.groups.length === 0 && !showCreate}
        <div class="card empty">
          <h3>Start or join a chama</h3>
          <p class="small" style="margin-bottom: 1rem">
            Create your chama to set the contribution and invite members, or ask an admin for an invite code.
          </p>
          <button class="btn btn-primary" onclick={() => (showCreate = true)}>Create a chama</button>
        </div>
      {:else if view === 'dashboard'}
        <Dashboard onnav={(next) => (view = next)} />
      {:else if view === 'members'}
        <Members />
      {:else}
        <PaymentSettings />
      {/if}
    </section>
  </div>
</div>

{#if showCreate}
  <CreateGroup onclose={() => (showCreate = false)} oncreated={created} />
{/if}
