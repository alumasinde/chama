<script lang="ts">
  import { onMount } from 'svelte';
  import { ApiFailure, api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import Icon from './Icon.svelte';

  let {
    title = 'Confirm with your PIN',
    subtitle = 'Your PIN authorises this ledger change.',
    confirmLabel = 'Confirm',
    busy = false,
    error = '',
    onconfirm,
    onclose,
  }: {
    title?: string;
    subtitle?: string;
    confirmLabel?: string;
    busy?: boolean;
    error?: string;
    onconfirm: (token: string) => Promise<void> | void;
    onclose: () => void;
  } = $props();

  let pin = $state('');
  let localBusy = $state(false);
  let localError = $state('');
  let pinInput: HTMLInputElement | undefined = $state();

  onMount(() => {
    pinInput?.focus();
  });

  async function submit() {
    if (!session.access || pin.length !== 4) return;
    localBusy = true;
    localError = '';
    try {
      const verified = await api<{ step_up_token: string }>('/auth/pin/verify', {
        method: 'POST',
        auth: session.access,
        body: { pin },
        retry: false,
      });
      await onconfirm(verified.step_up_token);
      pin = '';
    } catch (err) {
      localError = err instanceof ApiFailure ? err.message : 'Could not verify that PIN.';
    } finally {
      localBusy = false;
    }
  }
</script>

<div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget && !localBusy) onclose(); }}>
  <div class="modal modal-small" role="dialog" aria-modal="true" aria-label={title}>
    <div class="modal-head">
      <div class="modal-glyph"><Icon name="welfare" size={22} /></div>
      <button class="icon-btn" type="button" onclick={onclose} disabled={localBusy} aria-label="Close"><Icon name="close" size={18} /></button>
    </div>
    <h2>{title}</h2>
    <p class="muted small" style="margin: 0.35rem 0 1rem">{subtitle}</p>
    {#if error}<p class="error" style="margin-bottom: 0.75rem">{error}</p>{/if}
    {#if localError}<p class="error" style="margin-bottom: 0.75rem">{localError}</p>{/if}
    <form onsubmit={(event) => { event.preventDefault(); void submit(); }}>
      <label for="step-pin">4-digit PIN</label>
      <input
        id="step-pin"
        class="otp-input"
        bind:this={pinInput}
        bind:value={pin}
        type="password"
        maxlength="4"
        inputmode="numeric"
        autocomplete="current-password"
      />
      <button class="btn btn-green full-width" type="submit" disabled={localBusy || busy || pin.length !== 4} style="margin-top: 1rem">
        {localBusy ? 'Checking…' : confirmLabel}
      </button>
    </form>
    <p class="secure-line"><Icon name="check" size={14} /> Step-up approval protects every payout.</p>
  </div>
</div>
