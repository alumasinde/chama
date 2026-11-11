<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, canManagePayments, session } from '../lib/session.svelte';
  import type { PaymentSettings } from '../lib/types';

  let settings = $state<PaymentSettings | null>(null);
  let shortcodeType = $state('paybill');
  let shortcode = $state('');
  let environment = $state('sandbox');
  let template = $state('CHAMA-{member_short}-{period}');
  let consumerKey = $state('');
  let consumerSecret = $state('');
  let passkey = $state('');
  let callbackUrl = $state('');
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let fields = $state<Record<string, string>>({});
  let notice = $state('');

  const group = $derived(activeGroup());

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    try {
      const result = await api<PaymentSettings>(
        `/groups/${session.activeGroupId}/payment-settings`,
        { auth: session.access },
      );
      settings = result;
      if (result.configured) {
        shortcodeType = result.shortcode_type;
        shortcode = result.shortcode;
        environment = result.daraja_environment;
        template = result.account_reference_template;
      }
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load M-Pesa settings.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    callbackUrl = '';
    void load();
  });

  async function save() {
    if (!session.activeGroupId || !session.access) return;
    error = '';
    fields = {};
    notice = '';
    busy = true;
    try {
      const body: Record<string, unknown> = {
        shortcode_type: shortcodeType,
        shortcode,
        daraja_environment: environment,
        account_reference_template: template,
      };
      if (consumerKey) body.consumer_key = consumerKey;
      if (consumerSecret) body.consumer_secret = consumerSecret;
      if (passkey) body.passkey = passkey;
      const result = await api<PaymentSettings>(
        `/groups/${session.activeGroupId}/payment-settings`,
        { method: 'PUT', auth: session.access, body },
      );
      settings = result;
      callbackUrl = result.callback_url ?? '';
      consumerKey = '';
      consumerSecret = '';
      passkey = '';
      notice = 'Saved. Copy the callback URL into your Daraja app.';
    } catch (err) {
      if (err instanceof ApiFailure) {
        error = err.message;
        fields = err.fields ?? {};
      } else {
        error = 'Could not save those settings.';
      }
    } finally {
      busy = false;
    }
  }
</script>

<div class="section-head">
  <div>
    <h1>M-Pesa settings</h1>
    <p class="muted small">Your chama's own shortcode. No money is held by this platform.</p>
  </div>
</div>

{#if !canManagePayments()}
  <p class="notice">Only admins and treasurers can change these settings.</p>
{:else if loading}
  <div class="card empty">Loading…</div>
{:else}
  {#if !settings?.configured}
    <p class="notice">No shortcode yet. Add your Daraja credentials to start collecting contributions.</p>
  {:else if settings?.is_verified}
    <p class="notice">Shortcode verified {settings.verified_at ? new Date(settings.verified_at).toLocaleDateString('en-KE') : ''}.</p>
  {:else}
    <p class="notice">
      Saved but not verified yet. Run <strong>Verify</strong> in the Chama app, then send a KES 1 test prompt, before
      telling members to pay.
    </p>
  {/if}

  {#if error}<p class="error">{error}</p>{/if}
  {#if notice}<p class="notice">{notice}</p>{/if}

  <form class="card" style="padding: 1.25rem" onsubmit={(event) => { event.preventDefault(); void save(); }}>
    <div class="form-grid">
      <div>
        <label for="type">Shortcode type</label>
        <select id="type" bind:value={shortcodeType}>
          <option value="paybill">Paybill</option>
          <option value="till">Buy Goods (Till)</option>
        </select>
        {#if fields.shortcode_type}<p class="small error" style="margin-top: 0.4rem">{fields.shortcode_type}</p>{/if}
      </div>
      <div>
        <label for="shortcode">Shortcode</label>
        <input id="shortcode" bind:value={shortcode} inputmode="numeric" placeholder="e.g. 247247" />
        {#if fields.shortcode}<p class="small error" style="margin-top: 0.4rem">{fields.shortcode}</p>{/if}
      </div>
      <div>
        <label for="env">Daraja environment</label>
        <select id="env" bind:value={environment}>
          <option value="sandbox">Sandbox</option>
          <option value="production">Production</option>
        </select>
        {#if fields.daraja_environment}<p class="small error" style="margin-top: 0.4rem">{fields.daraja_environment}</p>{/if}
      </div>
      <div>
        <label for="template">Account reference</label>
        <input id="template" bind:value={template} />
        {#if fields.account_reference_template}<p class="small error" style="margin-top: 0.4rem">{fields.account_reference_template}</p>{/if}
      </div>
      <div class="full">
        <label for="key">Consumer key {#if settings?.configured}<span class="muted">— saved {settings.consumer_key_masked}</span>{/if}</label>
        <input id="key" bind:value={consumerKey} autocomplete="off" placeholder={settings?.configured ? 'Leave blank to keep the saved key' : 'From the Daraja portal'} />
        {#if fields.consumer_key}<p class="small error" style="margin-top: 0.4rem">{fields.consumer_key}</p>{/if}
      </div>
      <div>
        <label for="secret">Consumer secret {#if settings?.configured}<span class="muted">— saved {settings.consumer_secret_masked}</span>{/if}</label>
        <input id="secret" bind:value={consumerSecret} type="password" autocomplete="off" placeholder={settings?.configured ? 'Leave blank to keep' : 'Consumer secret'} />
        {#if fields.consumer_secret}<p class="small error" style="margin-top: 0.4rem">{fields.consumer_secret}</p>{/if}
      </div>
      <div>
        <label for="passkey">Lipa na M-Pesa passkey {#if settings?.configured}<span class="muted">— saved {settings.passkey_masked}</span>{/if}</label>
        <input id="passkey" bind:value={passkey} type="password" autocomplete="off" placeholder={settings?.configured ? 'Leave blank to keep' : 'Passkey'} />
        {#if fields.passkey}<p class="small error" style="margin-top: 0.4rem">{fields.passkey}</p>{/if}
      </div>
      <div class="full">
        <button class="btn btn-primary" type="submit" disabled={busy}>{busy ? 'Saving…' : 'Save settings'}</button>
      </div>
    </div>
  </form>

  {#if callbackUrl}
    <div class="card" style="padding: 1.25rem">
      <h2 style="margin-bottom: 0.5rem">Callback URL</h2>
      <p class="muted small" style="margin-bottom: 0.75rem">
        Paste this into the Daraja app once. It contains a secret, so treat it like a password.
      </p>
      <div class="invite" style="display: block">
        <code style="font-size: 0.8rem; letter-spacing: 0; word-break: break-all">{callbackUrl}</code>
      </div>
    </div>
  {/if}

  {#if settings?.configured}
    <p class="muted small">Shortcode {settings.shortcode} · {settings.shortcode_type} · {settings.daraja_environment}</p>
  {/if}
{/if}
