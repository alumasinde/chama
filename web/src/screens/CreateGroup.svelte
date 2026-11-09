<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import type { Group } from '../lib/types';

  let { onclose, oncreated }: { onclose: () => void; oncreated: () => void } = $props();

  let name = $state('');
  let description = $state('');
  let amount = $state('1000.00');
  let frequency = $state('monthly');
  let day = $state(1);
  let grace = $state(3);
  let busy = $state(false);
  let error = $state('');
  let fields = $state<Record<string, string>>({});

  async function submit() {
    error = '';
    fields = {};
    busy = true;
    try {
      const group = await api<Group>('/groups', {
        method: 'POST',
        auth: session.access,
        body: {
          name,
          ...(description ? { description } : {}),
          contribution_amount: amount,
          contribution_frequency: frequency,
          contribution_day: Number(day),
          late_grace_days: Number(grace),
        },
      });
      session.activeGroupId = group.id;
      oncreated();
    } catch (err) {
      if (err instanceof ApiFailure) {
        error = err.message;
        fields = err.fields ?? {};
      } else {
        error = 'Could not create the chama.';
      }
    } finally {
      busy = false;
    }
  }
</script>

<div class="modal-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) onclose(); }}>
  <div class="modal" role="dialog" aria-modal="true" aria-label="Create a chama">
    <div class="section-head" style="margin-bottom: 1rem">
      <h1 style="font-size: 1.25rem">Create a chama</h1>
      <button class="btn btn-ghost" onclick={onclose} aria-label="Close">✕</button>
    </div>
    <form class="stack" onsubmit={(event) => { event.preventDefault(); void submit(); }} style="display: grid; gap: 1rem">
      <div>
        <label for="g-name">Chama name</label>
        <input id="g-name" bind:value={name} placeholder="e.g. Umoja Women Group" />
        {#if fields.name}<p class="small error" style="margin-top: 0.4rem">{fields.name}</p>{/if}
      </div>
      <div>
        <label for="g-desc">Description (optional)</label>
        <textarea id="g-desc" bind:value={description} rows="2" placeholder="What this chama is for"></textarea>
      </div>
      <div class="form-grid">
        <div>
          <label for="g-amount">Contribution amount (KES)</label>
          <input id="g-amount" bind:value={amount} inputmode="decimal" />
          {#if fields.contribution_amount}<p class="small error" style="margin-top: 0.4rem">{fields.contribution_amount}</p>{/if}
        </div>
        <div>
          <label for="g-freq">Frequency</label>
          <select id="g-freq" bind:value={frequency}>
            <option value="weekly">Weekly</option>
            <option value="biweekly">Every two weeks</option>
            <option value="monthly">Monthly</option>
            <option value="quarterly">Quarterly</option>
          </select>
        </div>
        <div>
          <label for="g-day">Due day</label>
          <input id="g-day" type="number" min="0" max="28" bind:value={day} />
          {#if fields.contribution_day}<p class="small error" style="margin-top: 0.4rem">{fields.contribution_day}</p>{/if}
        </div>
        <div>
          <label for="g-grace">Grace days</label>
          <input id="g-grace" type="number" min="0" max="30" bind:value={grace} />
          {#if fields.late_grace_days}<p class="small error" style="margin-top: 0.4rem">{fields.late_grace_days}</p>{/if}
        </div>
      </div>
      {#if error}<p class="error">{error}</p>{/if}
      <div style="display: flex; gap: 0.75rem; justify-content: flex-end">
        <button class="btn btn-secondary" type="button" onclick={onclose}>Cancel</button>
        <button class="btn btn-primary" type="submit" disabled={busy || name.trim().length < 2}>
          {busy ? 'Creating…' : 'Create chama'}
        </button>
      </div>
    </form>
  </div>
</div>
