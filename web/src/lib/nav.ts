export const views = [
  'overview',
  'chamas',
  'members',
  'transactions',
  'loans',
  'fines',
  'welfare',
  'rotation',
  'reports',
  'audit',
  'settings',
  'profile',
  'marketplace',
] as const;

export type View = (typeof views)[number];

export function isView(value: string): value is View {
  return (views as readonly string[]).includes(value);
}

export function readView(): View {
  const raw = window.location.hash.replace(/^#\/?/, '').split('?')[0];
  return isView(raw) ? raw : 'overview';
}

export const viewTitles: Record<View, string> = {
  overview: 'Overview',
  chamas: 'My chama',
  members: 'Members',
  transactions: 'Transactions',
  loans: 'Loans',
  fines: 'Fines',
  welfare: 'Welfare',
  rotation: 'Rotation',
  reports: 'Reports',
  audit: 'Audit log',
  settings: 'M-Pesa settings',
  profile: 'Profile',
  marketplace: 'Marketplace',
};
