<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { clearPendingInvite, normalizeInviteCode, rememberInviteCode } from '../lib/invite';
  import { session } from '../lib/session.svelte';
  import type { InvitePreview, JoinResult } from '../lib/types';

  let { code }: { code: string } = $props();

  const normalized = $derived(normalizeInviteCode(code));
  const signedIn = $derived(Boolean(session.user && session.access));
  let preview = $state<InvitePreview | null>(null);
  const adminLine = $derived(
    preview?.admin_first_name
      ? `${preview.admin_first_name} invited you to ${preview.group_name}.`
      : 'A chama admin invited you.',
  );
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let joined = $state<JoinResult | null>(null);
  let alreadyMember = $state(false);

  $effect(() => {
    const value = normalized;
    if (!value) {
      loading = false;
      error = 'This invite link is incomplete.';
      return;
    }
    void load(value);
  });

  async function load(value: string) {
    loading = true;
    error = '';
    try {
      preview = await api<InvitePreview>(`/invites/${encodeURIComponent(value)}`, { retry: false });
    } catch (err) {
      preview = null;
      error = err instanceof ApiFailure ? err.message : 'This invite could not be loaded.';
    } finally {
      loading = false;
    }
  }

  function goToApp() {
    clearPendingInvite();
    window.location.assign(signedIn ? '/app#/overview' : '/');
  }

  function signIn() {
    rememberInviteCode(normalized);
    window.location.assign('/login');
  }

  function notNow() {
    clearPendingInvite();
    window.location.assign(signedIn ? '/app#/overview' : '/');
  }

  async function requestJoin() {
    if (!session.access) {
      signIn();
      return;
    }
    busy = true;
    error = '';
    try {
      joined = await api<JoinResult>('/groups/join', {
        method: 'POST',
        auth: session.access,
        body: { invite_code: normalized },
      });
      clearPendingInvite();
    } catch (err) {
      if (err instanceof ApiFailure && err.code === 'already_member') {
        alreadyMember = true;
        clearPendingInvite();
      } else {
        error = err instanceof ApiFailure ? err.message : 'Could not send your request. Try again.';
      }
    } finally {
      busy = false;
    }
  }

</script>

<div class="auth-wrap invite-wrap">
  <aside class="auth-hero">
    <a class="brand" href="/" aria-label="{session.appName} home">{session.appName}</a>
    <div>
      <p class="invite-kicker">Chama invite</p>
      <h2>{preview ? `Join ${preview.group_name}` : 'You are invited'}</h2>
      <p>
        {preview
          ? `${adminLine} Review the chama terms, then ask to join. An admin approves every new member.`
          : 'A chama is waiting for you. Open the link from your invite to see the group and send a request.'}
      </p>
      <div class="auth-points">
        <span>One shared ledger for contributions and payouts</span>
        <span>Loans, welfare and rotation in one place</span>
        <span>Your chama keeps its own M-Pesa shortcode</span>
      </div>
    </div>
    <p class="small">Money moves directly between members and your chama's shortcode.</p>
  </aside>

  <section class="auth-panel">
    <div class="auth-card card invite-card">
      {#if loading}
        <h1>Opening invite…</h1>
        <p class="muted small">Checking the chama behind this link.</p>
      {:else if joined}
        <span class="status-pill amber"><i></i>Pending approval</span>
        <h1>Request sent</h1>
        <p class="muted small">
          Your request to join <strong>{joined.group_name}</strong> is waiting for an admin.
          {joined.message}
        </p>
        <div class="invite-meta">
          <div><span>Chama</span><strong>{joined.group_name}</strong></div>
          <div><span>Status</span><strong>Pending</strong></div>
        </div>
        <button class="btn btn-primary full-width" type="button" onclick={goToApp}>Go to my chama</button>
      {:else if alreadyMember}
        <span class="status-pill green"><i></i>Member</span>
        <h1>You're already in</h1>
        <p class="muted small">This account is already an active member of this chama.</p>
        <button class="btn btn-primary full-width" type="button" onclick={goToApp}>Go to my chama</button>
      {:else if error && !preview}
        <span class="status-pill red"><i></i>Invite unavailable</span>
        <h1>This invite isn't available</h1>
        <p class="muted small">{error}</p>
        <p class="muted small">Ask the chama admin for a fresh link or the 8-character code.</p>
        <a class="btn btn-secondary full-width" href="/">Back to Chama Ledger</a>
      {:else if preview}
        <p class="page-kicker">You're invited</p>
        <h1>Join {preview.group_name}</h1>
        <p class="muted small">
          {preview.admin_first_name ? `${preview.admin_first_name} invited you.` : 'A chama admin invited you.'}
          Send a request and an admin will approve you.
        </p>
        <div class="invite-meta">
          <div><span>Contribution</span><strong>{preview.currency} {preview.contribution_amount} · {preview.contribution_frequency}</strong></div>
          <div><span>Active members</span><strong>{preview.active_members}</strong></div>
          <div><span>Invite code</span><strong class="mono">{normalized}</strong></div>
        </div>
        {#if signedIn}
          <p class="notice">Signed in as {session.user?.display_name}.</p>
          <button class="btn btn-primary full-width" type="button" onclick={() => void requestJoin()} disabled={busy}>
            {busy ? 'Sending request…' : 'Request to join'}
          </button>
        {:else}
          <p class="muted small">Sign in or create an account first. We'll bring you back to this invite.</p>
          <button class="btn btn-primary full-width" type="button" onclick={signIn}>
            Sign in to request to join
          </button>
        {/if}
        {#if error}<p class="error">{error}</p>{/if}
        <button class="btn btn-ghost full-width" type="button" onclick={notNow}>Not now</button>
      {/if}
    </div>
  </section>
</div>
