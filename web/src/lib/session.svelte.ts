import { api, setRefreshHandler } from './api';
import type { AuthSession, Group, Meta, User } from './types';

const STORAGE_KEY = 'chama.session.v1';

// Tokens live in sessionStorage so closing the tab ends the browser session.
export const session = $state({
  appName: 'Chama Ledger',
  user: null as User | null,
  access: null as string | null,
  refreshToken: null as string | null,
  groups: [] as Group[],
  pendingGroups: [] as Group[],
  activeGroupId: null as string | null,
});

export function activeGroup(): Group | null {
  return session.groups.find((group) => group.id === session.activeGroupId) ?? null;
}

export function isAdmin(): boolean {
  return activeGroup()?.role === 'admin';
}

export function canManagePayments(): boolean {
  const role = activeGroup()?.role;
  return role === 'admin' || role === 'treasurer';
}

export function applyAuth(auth: AuthSession) {
  session.access = auth.access_token;
  session.refreshToken = auth.refresh_token;
  session.user = auth.user;
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ refresh: auth.refresh_token, user: auth.user }));
  } catch {
    // Private browsing may block storage; the in-memory session still works.
  }
}

export async function restore(): Promise<void> {
  let raw: string | null = null;
  try {
    raw = sessionStorage.getItem(STORAGE_KEY);
  } catch {
    return;
  }
  if (!raw) return;
  try {
    const saved = JSON.parse(raw) as { refresh?: string; user?: User };
    if (!saved.refresh) return;
    session.refreshToken = saved.refresh;
    // Wait for the new access token before the shell mounts and loads chamas.
    await refresh();
  } catch {
    try {
      sessionStorage.removeItem(STORAGE_KEY);
    } catch {
      // ignore
    }
  }
}

export function signOut(remote = true) {
  if (remote && session.access) {
    api('/auth/logout', { method: 'POST', auth: session.access }).catch(() => undefined);
  }
  session.user = null;
  session.access = null;
  session.refreshToken = null;
  session.groups = [];
  session.pendingGroups = [];
  session.activeGroupId = null;
  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}

export async function refresh(): Promise<boolean> {
  if (!session.refreshToken) return false;
  try {
    const auth = await api<AuthSession>('/auth/token/refresh', {
      method: 'POST',
      body: { refresh_token: session.refreshToken },
      retry: false,
    });
    applyAuth(auth);
    return true;
  } catch {
    signOut(false);
    return false;
  }
}

export async function loadGroups(): Promise<void> {
  if (!session.access) return;
  const result = await api<{ data: Group[] }>('/groups', { auth: session.access });
  const active = result.data.filter((group) => group.status === 'active');
  session.pendingGroups = result.data.filter((group) => group.status === 'pending');
  session.groups = active;
  if (!session.activeGroupId || !active.some((group) => group.id === session.activeGroupId)) {
    session.activeGroupId = active[0]?.id ?? null;
  }
}

export async function loadBranding(): Promise<void> {
  try {
    const meta = await api<Meta>('/meta', { retry: false });
    session.appName = meta.app_name;
    document.title = meta.app_name;
  } catch {
    // Branding is cosmetic; the default name is fine offline.
  }
}

setRefreshHandler(refresh);
