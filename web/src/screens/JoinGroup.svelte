<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { normalizeInviteCode } from '../lib/invite';
  import { loadGroups, session } from '../lib/session.svelte';
  import type { JoinResult } from '../lib/types';
  import Icon from '../components/Icon.svelte';

  let { onclose }: { onclose: () => void } = $props();

  let code = $state('');
  let busy = $state(false);
  let error = $state('');
  let joined = $state<JoinResult | null>(null);
  let alreadyMember = $state(false);

  async function submit() {
    if (!session.access) {
      error = 'Sign in again to join a chama.';
      return;
    }
    const value = normalizeInviteCode(code);
    if (value.length !== 8) {
      error = 'Enter the 8-character code your admin shared.';
      return;
    }
    busy = true;
    error = '';
    try {
      joined = await api<JoinResult>('/groups/join', {
        method: 'POST',
        auth: session.access,
        body: { invite_code: value },
      });
      await loadGroups().catch(() => undefined);
    } catch (err) {
      if (err instanceof ApiFailure && err.code === 'already_member') {
        alreadyMember = true;
      } else {
        error = err instanceof ApiFailure ? err.message : 'Could not send that request. Try again.';
      }
    } finally {
      busy = false;
    }
  }
</script>

<div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) onclose(); }}>
  <div class="modal" role="dialog" aria-modal="true" aria-label="Join a chama">
    <div class="modal-head">
      <div><h2>{joined || alreadyMember ? 'Join request' : 'Join a chama'}</h2><p>{joined || alreadyMember ? 'Your membership status.' : 'Use the 8-character invite code from an admin.'}</p></div>
      <button class="icon-btn" type="button" onclick={onclose} aria-label="Close"><Icon name="close" size={18} /></button>
    </div>

    {#if joined}
      <div class="form-stack">
        <span class="status-pill amber"><i></i>Pending approval</span>
        <p><strong>{joined.group_name}</strong> received your request.</p>
        <p class="muted small">{joined.message} You'll see the chama after an admin approves you.</p>
        <div class="modal-actions"><button class="btn btn-primary" type="button" onclick={onclose}>Done</button></div>
      </div>
    {:else if alreadyMember}
      <div class="form-stack">
        <span class="status-pill green"><i></i>Member</span>
        <p>This account is already an active member of that chama.</p>
        <div class="modal-actions"><button class="btn btn-primary" type="button" onclick={onclose}>Done</button></div>
      </div>
    {:else}
      <form class="form-stack" onsubmit={(event) => { event.preventDefault(); void submit(); }}>
        <div>
          <label for="join-code">Invite code</label>
          <input id="join-code" bind:value={code} maxlength="12" autocomplete="off" placeholder="e.g. Y27MEN2H" class="mono" />
          <p class="footnote">Letters and numbers only. The code is not case-sensitive.</p>
        </div>
        {#if error}<p class="error">{error}</p>{/if}
        <div class="modal-actions">
          <button class="btn btn-secondary" type="button" onclick={onclose}>Cancel</button>
          <button class="btn btn-primary" type="submit" disabled={busy || code.trim().length < 8}>{busy ? 'Sending…' : 'Request to join'}</button>
        </div>
      </form>
    {/if}
  </div>
</div>
