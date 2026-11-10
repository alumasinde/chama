export function money(value: string | number | null | undefined, currency = 'KES'): string {
  if (value === null || value === undefined || value === '') return '—';
  const number = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(number)) return '—';
  return `${currency} ${number.toLocaleString('en-KE', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

export function number(value: string | number | null | undefined): number {
  if (value === null || value === undefined || value === '') return 0;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function dateShort(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString('en-KE', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function dateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('en-KE', {
    day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  });
}

export function monthDay(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString('en-KE', { day: 'numeric', month: 'short' });
}

export function titleCase(value: string | null | undefined): string {
  if (!value) return '—';
  return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function initials(name: string | null | undefined): string {
  if (!name) return '?';
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join('').toUpperCase();
}

export function tone(status: string | null | undefined): string {
  switch ((status ?? '').toLowerCase()) {
    case 'active':
    case 'completed':
    case 'paid':
    case 'approved':
    case 'done':
    case 'for':
      return 'green';
    case 'pending':
    case 'pending_approval':
    case 'pending_guarantors':
    case 'queued':
    case 'running':
    case 'unpaid':
      return 'amber';
    case 'rejected':
    case 'failed':
    case 'cancelled':
    case 'reversed':
    case 'suspended':
    case 'exited':
    case 'defaulted':
    case 'against':
      return 'red';
    case 'draft':
    case 'abstain':
      return 'grey';
    default:
      return 'purple';
  }
}

export function percent(part: number, total: number): number {
  if (!total) return 0;
  return Math.max(0, Math.min(100, Math.round((part / total) * 100)));
}
