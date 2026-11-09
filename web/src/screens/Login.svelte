<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { applyAuth, session } from '../lib/session.svelte';
  import type { AuthSession } from '../lib/types';

  let step = $state<'phone' | 'otp' | 'register' | 'password'>('phone');
  let phone = $state('');
  let code = $state('');
  let devCode = $state('');
  let password = $state('');
  let firstName = $state('');
  let lastName = $state('');
  let pin = $state('');
  let newPassword = $state('');
  let registrationToken = $state('');
  let error = $state('');
  let fields = $state<Record<string, string>>({});
  let busy = $state(false);

  function fail(err: unknown) {
    if (err instanceof ApiFailure) {
      error = err.message;
      fields = err.fields ?? {};
    } else {
      error = 'Network error. Check your connection and try again.';
    }
  }

  async function requestCode() {
    error = '';
    fields = {};
    busy = true;
    try {
      const result = await api<{ dev_code?: string }>('/auth/otp/request', {
        method: 'POST',
        body: { phone_number: phone, purpose: 'login' },
      });
      devCode = result.dev_code ?? '';
      if (devCode) code = devCode;
      step = 'otp';
    } catch (err) {
      fail(err);
    } finally {
      busy = false;
    }
  }

  async function verifyCode() {
    error = '';
    fields = {};
    busy = true;
    try {
      const result = await api<{
        new_user: boolean;
        registration_token?: string;
        session?: AuthSession;
      }>('/auth/otp/verify', {
        method: 'POST',
        body: { phone_number: phone, code, purpose: 'login' },
      });
      if (result.session) {
        applyAuth(result.session);
      } else if (result.new_user && result.registration_token) {
        registrationToken = result.registration_token;
        step = 'register';
      }
    } catch (err) {
      fail(err);
    } finally {
      busy = false;
    }
  }

  async function register() {
    error = '';
    fields = {};
    busy = true;
    try {
      const auth = await api<AuthSession>('/auth/register', {
        method: 'POST',
        auth: registrationToken,
        body: {
          first_name: firstName,
          last_name: lastName,
          pin,
          ...(newPassword ? { password: newPassword } : {}),
        },
      });
      applyAuth(auth);
    } catch (err) {
      fail(err);
    } finally {
      busy = false;
    }
  }

  async function passwordLogin() {
    error = '';
    fields = {};
    busy = true;
    try {
      const auth = await api<AuthSession>('/auth/login', {
        method: 'POST',
        body: { phone_number: phone, password },
      });
      applyAuth(auth);
    } catch (err) {
      fail(err);
    } finally {
      busy = false;
    }
  }
</script>

<div class="auth-wrap">
  <aside class="auth-hero">
    <div class="brand">{session.appName}</div>
    <div>
      <h2>Your chama, kept straight.</h2>
      <p>
        Contributions, loans, fines and merry-go-round turns in one ledger every member can
        trust. Each chama keeps its own M-Pesa shortcode.
      </p>
      <div class="auth-points">
        <span>Every shilling recorded, nothing held</span>
        <span>Approvals and roles your committee controls</span>
        <span>Works with your chama's own Paybill or Till</span>
      </div>
    </div>
    <p class="small">Money moves directly between members and your chama's shortcode.</p>
  </aside>

  <section class="auth-panel">
    <div class="auth-card card">
      {#if step === 'phone'}
        <h1>Karibu</h1>
        <p class="muted small" style="margin: 0.25rem 0 1.5rem">Sign in with your phone number.</p>
        <form class="stack" onsubmit={(event) => { event.preventDefault(); void requestCode(); }}>
          <div>
            <label for="phone">Phone number</label>
            <input id="phone" bind:value={phone} placeholder="0712 345 678" inputmode="tel" autocomplete="tel" />
            {#if fields.phone_number}<p class="small error" style="margin-top: 0.4rem">{fields.phone_number}</p>{/if}
          </div>
          {#if error}<p class="error">{error}</p>{/if}
          <button class="btn btn-primary" type="submit" disabled={busy || phone.length < 9}>
            {busy ? 'Sending…' : 'Send code'}
          </button>
          <button class="btn btn-ghost" type="button" onclick={() => { step = 'password'; error = ''; }}>
            Use a password instead
          </button>
        </form>
      {:else if step === 'otp'}
        <h1>Enter the code</h1>
        <p class="muted small" style="margin: 0.25rem 0 1.5rem">
          We sent a 6-digit code to {phone}.
        </p>
        <form class="stack" onsubmit={(event) => { event.preventDefault(); void verifyCode(); }}>
          <div>
            <label for="code">Verification code</label>
            <input id="code" class="otp-input" bind:value={code} maxlength="6" inputmode="numeric" autocomplete="one-time-code" />
            {#if fields.code}<p class="small error" style="margin-top: 0.4rem">{fields.code}</p>{/if}
          </div>
          {#if devCode}<p class="notice">Development code: {devCode}</p>{/if}
          {#if error}<p class="error">{error}</p>{/if}
          <button class="btn btn-primary" type="submit" disabled={busy || code.length !== 6}>
            {busy ? 'Checking…' : 'Continue'}
          </button>
          <button class="btn btn-ghost" type="button" onclick={() => { step = 'phone'; error = ''; }}>Change number</button>
        </form>
      {:else if step === 'register'}
        <h1>Create your account</h1>
        <p class="muted small" style="margin: 0.25rem 0 1.5rem">Just the basics, then you can join a chama.</p>
        <form class="stack" onsubmit={(event) => { event.preventDefault(); void register(); }}>
          <div class="form-grid">
            <div>
              <label for="first">First name</label>
              <input id="first" bind:value={firstName} autocomplete="given-name" />
              {#if fields.first_name}<p class="small error" style="margin-top: 0.4rem">{fields.first_name}</p>{/if}
            </div>
            <div>
              <label for="last">Last name</label>
              <input id="last" bind:value={lastName} autocomplete="family-name" />
              {#if fields.last_name}<p class="small error" style="margin-top: 0.4rem">{fields.last_name}</p>{/if}
            </div>
          </div>
          <div>
            <label for="pin">4-digit PIN</label>
            <input id="pin" bind:value={pin} maxlength="4" inputmode="numeric" type="password" autocomplete="new-password" />
            {#if fields.pin}<p class="small error" style="margin-top: 0.4rem">{fields.pin}</p>{/if}
          </div>
          <div>
            <label for="newpass">Password (optional)</label>
            <input id="newpass" bind:value={newPassword} type="password" autocomplete="new-password" placeholder="At least 8 characters" />
            {#if fields.password}<p class="small error" style="margin-top: 0.4rem">{fields.password}</p>{/if}
          </div>
          {#if error}<p class="error">{error}</p>{/if}
          <button class="btn btn-primary" type="submit" disabled={busy}>Create account</button>
        </form>
      {:else}
        <h1>Password sign-in</h1>
        <p class="muted small" style="margin: 0.25rem 0 1.5rem">Use the password you set on your account.</p>
        <form class="stack" onsubmit={(event) => { event.preventDefault(); void passwordLogin(); }}>
          <div>
            <label for="p-phone">Phone number</label>
            <input id="p-phone" bind:value={phone} placeholder="0712 345 678" inputmode="tel" autocomplete="tel" />
          </div>
          <div>
            <label for="p-pass">Password</label>
            <input id="p-pass" bind:value={password} type="password" autocomplete="current-password" />
          </div>
          {#if error}<p class="error">{error}</p>{/if}
          <button class="btn btn-primary" type="submit" disabled={busy || !phone || !password}>Sign in</button>
          <button class="btn btn-ghost" type="button" onclick={() => { step = 'phone'; error = ''; }}>Use a code instead</button>
        </form>
      {/if}
    </div>
  </section>
</div>
