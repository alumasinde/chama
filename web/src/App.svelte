<script lang="ts">
  import { onMount } from 'svelte';
  import Login from './screens/Login.svelte';
  import Shell from './screens/Shell.svelte';
  import { loadBranding, restore, session } from './lib/session.svelte';

  let ready = $state(false);

  onMount(async () => {
    void loadBranding();
    await restore();
    ready = true;
  });
</script>

{#if !ready}
  <div class="auth-wrap">
    <section class="auth-panel">
      <div class="auth-card card"><p class="muted">Loading your chama…</p></div>
    </section>
  </div>
{:else if session.user}
  <Shell />
{:else}
  <Login />
{/if}
