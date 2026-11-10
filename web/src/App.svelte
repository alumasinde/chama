<script lang="ts">
  import { onMount } from 'svelte';
  import Landing from './screens/Landing.svelte';
  import Login from './screens/Login.svelte';
  import Shell from './screens/Shell.svelte';
  import InviteLanding from './screens/InviteLanding.svelte';
  import { inviteCodeFromPath, pendingInviteCode } from './lib/invite';
  import { loadBranding, restore, session } from './lib/session.svelte';

  let ready = $state(false);
  let path = $state(normalizePath(window.location.pathname));
  let inviteCode = $state(inviteCodeFromPath());

  const signedIn = $derived(Boolean(session.user && session.access));
  const appHref = '/app#/overview';

  function normalizePath(value: string): string {
    const clean = value.replace(/\/+$/, '');
    return clean || '/';
  }

  function syncPath() {
    path = normalizePath(window.location.pathname);
    inviteCode = inviteCodeFromPath();
  }

  function pageMeta() {
    const app = session.appName;
    if (inviteCode) {
      return {
        title: `Join a chama | ${app}`,
        description: 'Review a chama invite and request to join the shared ledger.',
      };
    }
    if (path === '/login') {
      return {
        title: `Sign in | ${app}`,
        description: `Sign in to ${app} with your phone number.`,
      };
    }
    if (path === '/app') {
      return {
        title: `${app} | Your chama workspace`,
        description: 'Contributions, loans, welfare, fines, rotation and reports in one shared chama ledger.',
      };
    }
    return {
      title: `${app} | The shared ledger for chamas`,
      description:
        "A shared ledger for Kenyan chamas. Keep contributions, loans, welfare, fines and rotation turns straight while money moves on the chama's own M-Pesa shortcode.",
    };
  }

  function applyPageMeta() {
    const meta = pageMeta();
    document.title = meta.title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', meta.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', meta.title);
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', meta.description);
  }

  onMount(() => {
    syncPath();
    const sync = () => syncPath();
    window.addEventListener('popstate', sync);
    return () => window.removeEventListener('popstate', sync);
  });

  onMount(async () => {
    void loadBranding();
    await restore();
    ready = true;

    // Old bookmarks used /#/overview. Send them to the app URL, not the
    // marketing page, while leaving normal landing anchors alone.
    if (path === '/' && /^#\/[a-z]/.test(window.location.hash)) {
      window.location.replace(`/app${window.location.hash}`);
    }
  });

  $effect(() => {
    if (!ready) return;
    applyPageMeta();
  });

  $effect(() => {
    if (!ready) return;

    const pending = pendingInviteCode();
    if (path === '/app' && !signedIn) {
      window.location.replace('/login');
      return;
    }
    if (path === '/login' && signedIn) {
      window.location.replace(pending ? `/join/${encodeURIComponent(pending)}` : appHref);
    }
  });
</script>

{#if !ready}
  <div class="splash">
    <div class="splash-mark" aria-hidden="true">
      <span></span><span></span><span></span>
    </div>
    <h1>{session.appName}</h1>
    <p>Together · Save · Grow</p>
    <div class="splash-loader"><i></i></div>
  </div>
{:else if inviteCode}
  <InviteLanding code={inviteCode} />
{:else if path === '/app' && signedIn}
  <Shell />
{:else if path === '/login' && !signedIn}
  <Login />
{:else}
  <Landing {signedIn} />
{/if}
