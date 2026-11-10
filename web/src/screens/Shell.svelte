<script lang="ts">
  import { onMount } from 'svelte';
  import { activeGroup, isAdmin, loadGroups, session, signOut, canManagePayments } from '../lib/session.svelte';
  import { readView, viewTitles, type View } from '../lib/nav';
  import Icon from '../components/Icon.svelte';
  import Dashboard from './Dashboard.svelte';
  import MemberDashboard from './MemberDashboard.svelte';
  import Chamas from './Chamas.svelte';
  import Members from './Members.svelte';
  import Transactions from './Transactions.svelte';
  import Loans from './Loans.svelte';
  import Fines from './Fines.svelte';
  import Welfare from './Welfare.svelte';
  import Rotation from './Rotation.svelte';
  import Reports from './Reports.svelte';
  import Audit from './Audit.svelte';
  import PaymentSettings from './PaymentSettings.svelte';
  import Profile from './Profile.svelte';
  import Marketplace from './Marketplace.svelte';
  import CreateGroup from './CreateGroup.svelte';
  import JoinGroup from './JoinGroup.svelte';

  let view = $state<View>(readView());
  let showCreate = $state(false);
  let showJoin = $state(false);
  let error = $state('');
  let menuOpen = $state(false);
  let theme = $state<'light' | 'dark'>('light');

  const group = $derived(activeGroup());
  const admin = $derived(isAdmin());
  const payments = $derived(canManagePayments());
  const reportsRole = $derived(['admin', 'treasurer', 'secretary'].includes(group?.role ?? ''));
  const member = $derived(group?.role === 'member');
  const pageTitle = $derived(viewTitles[view]);

  type NavItem = { view: View; label: string; icon: string; show: boolean };
  const sections = $derived<Array<{ label: string; items: NavItem[] }>>([
    {
      label: 'Workspace',
      items: [
        { view: 'overview', label: 'Overview', icon: 'overview', show: true },
        { view: 'chamas', label: 'My chama', icon: 'chamas', show: true },
        { view: 'members', label: 'Members', icon: 'members', show: !member },
        { view: 'welfare', label: 'Welfare', icon: 'welfare', show: true },
        { view: 'rotation', label: 'Rotation', icon: 'rotation', show: true },
      ],
    },
    {
      label: 'Ledger',
      items: [
        { view: 'transactions', label: 'Transactions', icon: 'transactions', show: true },
        { view: 'loans', label: 'Loans', icon: 'loans', show: true },
        { view: 'fines', label: 'Fines', icon: 'fines', show: true },
      ],
    },
    {
      label: 'Manage',
      items: [
        { view: 'reports', label: 'Reports', icon: 'reports', show: reportsRole },
        { view: 'audit', label: 'Audit log', icon: 'audit', show: admin },
        { view: 'settings', label: 'M-Pesa settings', icon: 'settings', show: payments },
      ],
    },
  ]);

  onMount(() => {
    if (!window.location.hash || window.location.hash === '#/') {
      window.location.hash = '#/overview';
    }
    const sync = () => {
      view = readView();
      menuOpen = false;
    };
    window.addEventListener('hashchange', sync);
    try {
      const saved = localStorage.getItem('chama.theme');
      theme = saved === 'dark' ? 'dark' : 'light';
    } catch {
      // Storage can be blocked; light theme still works.
    }
    void refreshGroups();
    return () => window.removeEventListener('hashchange', sync);
  });

  $effect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem('chama.theme', theme);
    } catch {
      // ignore
    }
  });

  $effect(() => {
    if (view === 'audit' && !admin) go('overview');
    if (view === 'settings' && !payments) go('overview');
    if (view === 'reports' && !reportsRole) go('overview');
    if (view === 'members' && member) go('overview');
  });

  async function refreshGroups() {
    try {
      await loadGroups();
      error = '';
    } catch {
      error = 'Could not load your chamas. Refresh the page or sign in again.';
    }
  }

  function go(next: View) {
    if (view === next) {
      menuOpen = false;
      if (window.location.hash !== `#/${next}`) window.location.hash = `#/${next}`;
      return;
    }
    view = next;
    menuOpen = false;
    if (window.location.hash !== `#/${next}`) window.location.hash = `#/${next}`;
    document.querySelector('.content')?.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function created() {
    showCreate = false;
    await refreshGroups();
    go('overview');
  }

  function toggleTheme() {
    theme = theme === 'light' ? 'dark' : 'light';
  }
</script>

<div class="shell" class:menu-open={menuOpen}>
  <aside class="sidebar">
    <div class="sidebar-top">
      <a class="brand" href="#/overview" onclick={(event) => { event.preventDefault(); go('overview'); }}>
        <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="brand-copy">
          <strong>{session.appName}</strong>
          <small>Together · Save · Grow</small>
        </span>
      </a>
      <button class="sidebar-close icon-btn on-dark" type="button" onclick={() => (menuOpen = false)} aria-label="Close menu">
        <Icon name="close" size={18} />
      </button>
    </div>

    <nav class="side-nav" aria-label="Main navigation">
      {#each sections as section (section.label)}
        {#if section.items.some((item) => item.show)}
          <div class="nav-section">
            <p>{section.label}</p>
            {#each section.items.filter((item) => item.show) as item (item.view)}
              <button class="nav-item" class:active={view === item.view} type="button" onclick={() => go(item.view)}>
                <span class="nav-icon"><Icon name={item.icon} size={18} /></span>
                <span>{item.label}</span>
                {#if item.view === 'rotation' && group && group.role !== 'member'}<span class="nav-dot"></span>{/if}
              </button>
            {/each}
          </div>
        {/if}
      {/each}
    </nav>

    <div class="sidebar-bottom">
      <div class="ledger-note">
        <span class="ledger-icon"><Icon name="check" size={14} /></span>
        <div><strong>Ledger, not a wallet</strong><small>Money moves on your chama's shortcode.</small></div>
      </div>
      <div class="who">
        <div class="avatar avatar-light">{session.user?.first_name?.charAt(0)}{session.user?.last_name?.charAt(0)}</div>
        <div class="who-copy">
          <strong>{session.user?.display_name}</strong>
          <small>{group?.role ? `${group.role} · ${group.name}` : session.user?.phone_number}</small>
        </div>
        <button class="icon-btn on-dark" type="button" onclick={() => signOut()} aria-label="Sign out"><Icon name="logout" size={17} /></button>
      </div>
    </div>
  </aside>

  {#if menuOpen}
    <button class="scrim" type="button" aria-label="Close menu" onclick={() => (menuOpen = false)}></button>
  {/if}

  <div class="main">
    <header class="topbar">
      <button class="icon-btn menu-btn" type="button" onclick={() => (menuOpen = true)} aria-label="Open menu">
        <Icon name="menu" size={20} />
      </button>
      <div class="crumb">
        <span>Chama</span>
        <Icon name="chevron" size={13} />
        <strong>{pageTitle}</strong>
      </div>
      <span class="topbar-spacer"></span>
      {#if session.groups.length > 0}
        <label class="group-switch">
          <span class="group-dot"></span>
          <select bind:value={session.activeGroupId} aria-label="Active chama">
            {#each session.groups as item (item.id)}
              <option value={item.id}>{item.name}</option>
            {/each}
          </select>
          <Icon name="down" size={14} />
        </label>
      {/if}
      <button class="icon-btn" type="button" onclick={toggleTheme} aria-label="Toggle dark mode">
        <Icon name={theme === 'light' ? 'moon' : 'sun'} size={18} />
      </button>
      <button class="user-chip" type="button" onclick={() => go('profile')} aria-label="Open profile">
        <span class="avatar">{session.user?.first_name?.charAt(0)}{session.user?.last_name?.charAt(0)}</span>
        <span class="user-chip-copy"><strong>{session.user?.first_name}</strong><small>{group?.role ?? 'member'}</small></span>
      </button>
    </header>

    <section class="content">
      {#if error}<p class="error">{error}</p>{/if}
      {#if session.groups.length > 0 && session.pendingGroups.length > 0}
        <p class="notice">Pending approval: {session.pendingGroups.map((item) => item.name).join(', ')}. An admin will let you in shortly.</p>
      {/if}
      {#if session.groups.length === 0 && !showCreate}
        <div class="setup-hero">
          <span class="setup-kicker">Your first chama</span>
          <h1>Start something worth saving for.</h1>
          <p>Create a chama to set its contribution terms and invite your people. Every shilling stays on your own M-Pesa shortcode — this platform only keeps the ledger.</p>
          {#if session.pendingGroups.length > 0}
            <p class="notice" style="margin-top: 1rem; background: rgba(255,255,255,.1); color: #fff; border-color: rgba(255,255,255,.2)">Waiting for approval: {session.pendingGroups.map((item) => item.name).join(', ')}.</p>
          {/if}
          <div class="setup-actions">
            <button class="btn btn-secondary" type="button" onclick={() => (showJoin = true)}><Icon name="members" size={18} /> Join a chama</button>
            <button class="btn btn-green" type="button" onclick={() => (showCreate = true)}><Icon name="plus" size={18} /> Create a chama</button>
          </div>
          <div class="setup-points">
            <span><Icon name="check" size={15} /> One ledger every member can trust</span>
            <span><Icon name="check" size={15} /> Welfare, loans, fines and rotation</span>
            <span><Icon name="check" size={15} /> CSV and PDF reports</span>
          </div>
        </div>
      {:else if view === 'overview'}
        {#if member}<MemberDashboard onnav={go} />{:else}<Dashboard onnav={go} />{/if}
      {:else if view === 'chamas'}
        <Chamas onnav={go} oncreate={() => (showCreate = true)} onjoin={() => (showJoin = true)} />
      {:else if view === 'members'}
        <Members />
      {:else if view === 'transactions'}
        <Transactions />
      {:else if view === 'loans'}
        <Loans />
      {:else if view === 'fines'}
        <Fines />
      {:else if view === 'welfare'}
        <Welfare />
      {:else if view === 'rotation'}
        <Rotation />
      {:else if view === 'reports'}
        <Reports />
      {:else if view === 'audit'}
        <Audit />
      {:else if view === 'settings'}
        <PaymentSettings />
      {:else if view === 'profile'}
        <Profile onnav={go} />
      {:else}
        <Marketplace />
      {/if}
    </section>
  </div>
</div>

{#if showCreate}
  <CreateGroup onclose={() => (showCreate = false)} oncreated={created} />
{/if}

{#if showJoin}
  <JoinGroup onclose={() => (showJoin = false)} />
{/if}
