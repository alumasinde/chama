<script lang="ts">
  import { ApiFailure } from '../lib/api';
  import { exportReport } from '../lib/reports';
  import Icon from './Icon.svelte';

  let { reportCode, compact = false }: { reportCode: string; compact?: boolean } = $props();
  let busy = $state<'csv' | 'pdf' | null>(null);
  let error = $state('');

  async function run(format: 'csv' | 'pdf') {
    busy = format;
    error = '';
    try {
      await exportReport(reportCode, format);
    } catch (err) {
      error = err instanceof ApiFailure || err instanceof Error ? err.message : 'Export failed.';
    } finally {
      busy = null;
    }
  }
</script>

<div class="export-wrap" class:compact>
  <span class="export-label"><Icon name="download" size={14} /> Export</span>
  <button class="export-btn" type="button" onclick={() => void run('csv')} disabled={busy !== null}>
    {busy === 'csv' ? '…' : 'CSV'}
  </button>
  <button class="export-btn" type="button" onclick={() => void run('pdf')} disabled={busy !== null}>
    {busy === 'pdf' ? '…' : 'PDF'}
  </button>
  {#if error}<span class="export-error" title={error}>Export failed</span>{/if}
</div>
