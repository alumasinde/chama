const PENDING_KEY = 'chama.pendingInvite.v1';

export function normalizeInviteCode(raw: string): string {
  return raw
    .trim()
    .toUpperCase()
    .replace(/[\s-]/g, '')
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1');
}

export function inviteCodeFromPath(pathname: string = window.location.pathname): string {
  const match = pathname.match(/^\/join\/([^/]+)\/?$/);
  if (!match) return '';
  try {
    return normalizeInviteCode(decodeURIComponent(match[1]));
  } catch {
    return '';
  }
}

export function pendingInviteCode(): string {
  try {
    const code = normalizeInviteCode(sessionStorage.getItem(PENDING_KEY) ?? '');
    return code.length === 8 ? code : '';
  } catch {
    return '';
  }
}

export function rememberInviteCode(code: string): void {
  try {
    sessionStorage.setItem(PENDING_KEY, normalizeInviteCode(code));
  } catch {
    // The public landing page can still be used from the link itself.
  }
}

export function clearPendingInvite(): void {
  try {
    sessionStorage.removeItem(PENDING_KEY);
  } catch {
    // ignore
  }
}

export function inviteLink(code: string): string {
  return `${window.location.origin}/join/${encodeURIComponent(normalizeInviteCode(code))}`;
}
