<script lang="ts">
  import { ApiFailure, api } from '../lib/api';
  import { activeGroup, session } from '../lib/session.svelte';
  import { dateTime, titleCase } from '../lib/format';
  import type { AuditEntry } from '../lib/types';
  import Icon from '../components/Icon.svelte';
  import ExportButtons from '../components/ExportButtons.svelte';

  const group = $derived(activeGroup());
  let entries = $state<AuditEntry[]>([]);
  let loading = $state(true);
  let error = $state('');
  let action = $state('');
  let entity = $state('');
  let search = $state('');
  let selected = $state<AuditEntry | null>(null);

  const actions = $derived([...new Set(entries.map((entry) => entry.action))].sort());
  const entities = $derived([...new Set(entries.map((entry) => entry.entity_type))].sort());
  const filtered = $derived(entries.filter((entry) => {
    if (action && entry.action !== action) return false;
    if (entity && entry.entity_type !== entity) return false;
    if (search.trim() && !`${entry.actor} ${entry.action} ${entry.entity_type} ${entry.entity_public_id ?? ''}`.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  }));

  async function load() {
    if (!session.activeGroupId || !session.access) return;
    loading = true;
    error = '';
    try {
      const query = new URLSearchParams({ limit: '200' });
      if (action) query.set('action', action);
      if (entity) query.set('entity_type', entity);
      const result = await api<{ data: AuditEntry[] }>(`/groups/${session.activeGroupId}/audit-logs?${query}`, { auth: session.access });
      entries = result.data;
    } catch (err) {
      error = err instanceof ApiFailure ? err.message : 'Could not load the audit trail.';
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    session.activeGroupId;
    void load();
  });

  function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  function diffKeys(before: unknown, after: unknown): string[] {
    const keys = new Set<string>();
    if (isRecord(before)) Object.keys(before).forEach((key) => keys.add(key));
    if (isRecord(after)) Object.keys(after).forEach((key) => keys.add(key));
    return [...keys];
  }

  function valueAt(source: unknown, key: string): unknown {
    return isRecord(source) ? source[key] : undefined;
  }

  function display(value: unknown): string {
    if (value === undefined) return '—';
    if (value === null) return 'null';
    if (typeof value === 'object') return JSON.stringify(value);
    return String(value);
  }

  function changed(key: string): boolean {
    return JSON.stringify(valueAt(selected?.before, key)) !== JSON.stringify(valueAt(selected?.after, key));
  }
</script>

<div class="page-head">
  <div><p class="page-kicker">Accountability</p><h1>Audit log</h1><p>Who changed what, when, and the value before and after.</p></div>
  <div class="page-actions"><ExportButtons reportCode="audit" /><button class="btn btn-secondary" type="button" onclick={() => void load()}><Icon name="refresh" size={16} /> Refresh</button></div>
</div>

{#if error}<p class="error">{error}</p>{/if}

<section class="card table-card">
  <div class="filter-bar">
    <label class="search-field"><Icon name="search" size={16} /><input bind:value={search} placeholder="Search actor, action or entity" aria-label="Search audit log" /></label>
    <select bind:value={action} aria-label="Filter by action">
      <option value="">All actions</option>
      {#each actions as item (item)}<option value={item}>{titleCase(item)}</option>{/each}
    </select>
    <select bind:value={entity} aria-label="Filter by entity">
      <option value="">All entities</option>
      {#each entities as item (item)}<option value={item}>{titleCase(item)}</option>{/each}
    </select>
    <span class="filter-count">{filtered.length} entries</span>
  </div>

  {#if loading}
    <div class="skeleton-rows">{[1,2,3,4,5].map(() => '<div class="skeleton"></div>')}</div>
  {:else if filtered.length === 0}
    <div class="empty"><span class="empty-icon"><Icon name="audit" size={24} /></span><h3>No audit entries</h3><p>Member changes and exports will appear here.</p></div>
  {:else}
    <div class="table-wrap">
      <table>
        <thead><tr><th>When</th><th>Actor</th><th>Action</th><th>Entity</th><th>Values</th><th></th></tr></thead>
        <tbody>
          {#each filtered as entry (entry.id)}
            <tr class="clickable" onclick={() => (selected = entry)}>
              <td class="muted small nowrap">{dateTime(entry.created_at)}</td>
              <td><span class="person"><span class="avatar avatar-sm">{entry.actor.split(' ').map((part) => part[0]).slice(0, 2).join('')}</span>{entry.actor}</span></td>
              <td><span class="action-code">{entry.action}</span></td>
              <td><strong>{titleCase(entry.entity_type)}</strong>{#if entry.entity_public_id}<small class="muted mono">{entry.entity_public_id.slice(0, 8)}</small>{/if}</td>
              <td>{#if entry.before || entry.after}<span class="status-pill purple"><i></i>Before → after</span>{:else}<span class="muted small">No diff</span>{/if}</td>
              <td class="align-right"><Icon name="chevron" size={16} /></td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>

<p class="footnote">The audit table is append-only. Updates and deletes are rejected by the database, not just the interface.</p>

{#if selected}
  <div class="drawer-backdrop" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) selected = null; }}>
    <div class="drawer" role="dialog" aria-modal="true" aria-label="Audit entry detail">
      <div class="drawer-head">
        <div><span class="page-kicker">Audit entry</span><h2>{titleCase(selected.action)}</h2><p>{selected.actor} · {dateTime(selected.created_at)}</p></div>
        <button class="icon-btn" type="button" onclick={() => (selected = null)} aria-label="Close"><Icon name="close" size={19} /></button>
      </div>
      <div class="audit-meta">
        <div><span>Entity</span><strong>{titleCase(selected.entity_type)}</strong></div>
        <div><span>Entity ID</span><strong class="mono small">{selected.entity_public_id ?? '—'}</strong></div>
        <div><span>Entry</span><strong class="mono small">{selected.id.slice(0, 8)}</strong></div>
      </div>
      <h3 class="drawer-section-title">Field changes</h3>
      {#if diffKeys(selected.before, selected.after).length === 0}
        <div class="empty compact"><p>This entry has no structured diff.</p></div>
      {:else}
        <div class="diff-table">
          <div class="diff-head"><span>Field</span><span>Before</span><span>After</span></div>
          {#each diffKeys(selected.before, selected.after) as key (key)}
            <div class="diff-row" class:changed={changed(key)}>
              <span>{titleCase(key)}</span>
              <code>{display(valueAt(selected.before, key))}</code>
              <code>{display(valueAt(selected.after, key))}</code>
            </div>
          {/each}
        </div>
      {/if}
      <h3 class="drawer-section-title">Raw payload</h3>
      <div class="raw-grid">
        <div><span>Before</span><pre>{JSON.stringify(selected.before, null, 2)}</pre></div>
        <div><span>After</span><pre>{JSON.stringify(selected.after, null, 2)}</pre></div>
      </div>
      <p class="footnote">Group: {group?.name}. Personalised ledger data is never cached by the API.</p>
    </div>
  </div>
{/if}
