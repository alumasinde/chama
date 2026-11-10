<script lang="ts">
  let { name, size = 20, stroke = 1.8 }: { name: string; size?: number; stroke?: number } = $props();
</script>

<svg
  class="icon"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width={stroke}
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {#if name === 'overview'}
    <path d="M3 11.2 12 4l9 7.2" /><path d="M5.5 9.8V20h13V9.8" /><path d="M9.5 20v-5.5h5V20" />
  {:else if name === 'chamas'}
    <circle cx="9" cy="8" r="3" /><path d="M3.5 20c0-3.1 2.5-5.4 5.5-5.4s5.5 2.3 5.5 5.4" />
    <path d="M16 5.2a2.8 2.8 0 0 1 0 5.5" /><path d="M17.5 14.5c1.8.6 3 2.4 3 4.5" />
  {:else if name === 'members'}
    <circle cx="8" cy="8" r="3" /><circle cx="17" cy="8" r="2.5" opacity=".65" />
    <path d="M2.8 20c0-3.2 2.3-5.5 5.2-5.5s5.2 2.3 5.2 5.5" /><path d="M15 14.9c1 .3 1.8 1 2.2 2" />
  {:else if name === 'transactions'}
    <path d="M4 7h16" /><path d="m16 3 4 4-4 4" /><path d="M20 17H4" /><path d="m8 13-4 4 4 4" />
  {:else if name === 'loans'}
    <path d="M3 8.5h18v11H3z" /><path d="M3 8.5 5 4h14l2 4.5" /><path d="M15.5 14h2" />
  {:else if name === 'fines'}
    <path d="M12 3 2.8 20h18.4L12 3Z" /><path d="M12 9v4.5" /><path d="M12 17h.01" />
  {:else if name === 'welfare'}
    <path d="M20.8 5.8c-2-2-5.2-2-7.2 0L12 7.4l-1.6-1.6a5.1 5.1 0 0 0-7.2 7.2L12 21l8.8-8a5.1 5.1 0 0 0 0-7.2Z" />
  {:else if name === 'rotation'}
    <path d="M20 12a8 8 0 1 1-2.3-5.7" /><path d="M20 4v5h-5" /><circle cx="12" cy="12" r="2.5" />
  {:else if name === 'reports'}
    <path d="M4 20V4h11l5 5v11z" /><path d="M15 4v5h5" /><path d="M8 16v-3" /><path d="M12 16V9" /><path d="M16 16v-2" />
  {:else if name === 'audit'}
    <circle cx="11" cy="11" r="6.5" /><path d="m16 16 5 5" /><path d="M8 11h6" /><path d="M11 8v6" />
  {:else if name === 'settings'}
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z" />
  {:else if name === 'profile'}
    <circle cx="12" cy="8" r="3.5" /><path d="M4.5 21c0-4 3.2-6.5 7.5-6.5s7.5 2.5 7.5 6.5" />
  {:else if name === 'marketplace'}
    <path d="M4 9h16l-1 11H5L4 9Z" /><path d="M8 9V7a4 4 0 0 1 8 0v2" />
  {:else if name === 'plus'}
    <path d="M12 5v14" /><path d="M5 12h14" />
  {:else if name === 'arrow'}
    <path d="M5 12h14" /><path d="m14 7 5 5-5 5" />
  {:else if name === 'chevron'}
    <path d="m9 6 6 6-6 6" />
  {:else if name === 'down'}
    <path d="m6 9 6 6 6-6" />
  {:else if name === 'download'}
    <path d="M12 3v12" /><path d="m7 10 5 5 5-5" /><path d="M4 20h16" />
  {:else if name === 'check'}
    <path d="m4 12 5 5L20 6" />
  {:else if name === 'refresh'}
    <path d="M20 11a8 8 0 1 0-.4 3" /><path d="M20 4v7h-7" />
  {:else if name === 'copy'}
    <rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" />
  {:else if name === 'bell'}
    <path d="M18 9a6 6 0 1 0-12 0c0 7-3 7-3 7h18s-3 0-3-7" /><path d="M10 20h4" />
  {:else if name === 'logout'}
    <path d="M10 4H5v16h5" /><path d="M14 8l4 4-4 4" /><path d="M18 12H9" />
  {:else if name === 'search'}
    <circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" />
  {:else if name === 'close'}
    <path d="m6 6 12 12" /><path d="m18 6-12 12" />
  {:else if name === 'sun'}
    <circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
  {:else if name === 'moon'}
    <path d="M20 15.2A8.5 8.5 0 0 1 8.8 4 8.5 8.5 0 1 0 20 15.2Z" />
  {:else if name === 'menu'}
    <path d="M4 7h16M4 12h16M4 17h16" />
  {:else if name === 'edit'}
    <path d="M4 20h4l11-11-4-4L4 16v4Z" /><path d="m13.5 6.5 4 4" />
  {:else}
    <circle cx="12" cy="12" r="8" />
  {/if}
</svg>
