export type User = {
  id: string;
  phone_number: string;
  first_name: string;
  last_name: string;
  display_name: string;
  email: string | null;
  pin_set: boolean;
  has_password: boolean;
};

export type AuthSession = {
  access_token: string;
  refresh_token: string;
  user: User;
};

export type Group = {
  id: string;
  name: string;
  description: string | null;
  invite_code: string;
  currency: string;
  contribution_amount: string;
  contribution_frequency: string;
  contribution_day: number;
  late_grace_days: number;
  role: string;
  status: string;
  active_members: number;
  created_at: string;
};

export type InvitePreview = {
  group_name: string;
  admin_first_name: string;
  active_members: number;
  currency: string;
  contribution_amount: string;
  contribution_frequency: string;
};

export type JoinResult = {
  group_id: string;
  group_name: string;
  status: string;
  message: string;
};

export type Member = {
  user_id: string;
  first_name: string;
  last_name: string;
  display_name: string;
  role: string;
  status: string;
  joined_at: string | null;
};

export type PaymentSettings = {
  configured: boolean;
  shortcode_type: string;
  shortcode: string;
  account_reference_template: string;
  daraja_environment: string;
  consumer_key_masked: string;
  consumer_secret_masked: string;
  passkey_masked: string;
  is_verified: boolean;
  verified_at: string | null;
  updated_at: string | null;
  callback_url?: string;
};

export type ManualContribution = {
  transaction_id: string;
  member_id: string;
  amount: string;
  reference: string;
  recorded_at: string;
};

export type StkResult = {
  payment_request_id: string;
  checkout_request_id: string;
  status: string;
  amount: string;
  purpose: string;
};

export type Transaction = {
  id: string;
  user_id: string;
  member: string;
  type: string;
  status: 'pending' | 'completed' | 'failed' | 'reversed' | 'cancelled';
  channel: string | null;
  amount: string;
  reference_code: string | null;
  narration: string;
  period_label: string | null;
  created_at: string;
  completed_at: string | null;
};

export type Meta = {
  app_name: string;
  short_name: string;
  currency: string;
  primary_color: string;
  accent_color: string;
};

export type WelfareFund = {
  configured: boolean;
  name: string;
  monthly_amount: string;
  is_active: boolean;
  balance: string;
  contributed_total: string;
  paid_out_total: string;
  updated_at: string | null;
};

export type WelfareContribution = {
  id: string;
  user_id: string;
  member: string;
  amount: string;
  period_label: string;
  transaction_id: string | null;
  created_at: string;
};

export type WelfareClaim = {
  id: string;
  user_id: string;
  member: string;
  amount: string;
  reason: string;
  status: string;
  requested_at: string;
  decided_at: string | null;
  decided_by: string | null;
  comment: string | null;
  payout_transaction_id: string | null;
};

export type RotationSlot = {
  id: string;
  user_id: string;
  member: string;
  position: number;
  payout_date: string;
  payout_transaction_id: string | null;
  paid: boolean;
};

export type RotationCycle = {
  id: string;
  name: string;
  status: string;
  ordering_mode: string;
  contribution_amount: string;
  starts_on: string;
  member_count: number;
  draw_seed: string | null;
  slot_count: number;
  paid_count: number;
  created_at: string;
  completed_at: string | null;
  slots: RotationSlot[];
};

export type ProposalSummary = {
  id: string;
  status: string;
  quorum_percent: number;
  eligible_members: number;
  for: number;
  against: number;
  abstain: number;
  total: number;
  needed: number;
  opens_at: string;
  closes_at: string;
  closed_at: string | null;
  created_at: string;
};

export type Proposal = ProposalSummary & {
  cycle_id: string;
  proposed_by: string;
  result: { for: number; against: number; abstain: number; total: number; eligible: number; needed: number } | null;
  my_vote: { choice: string; cast_at: string } | null;
  slots: RotationSlot[];
};

export type Guarantor = {
  user_id: string;
  display_name: string;
  amount: string;
  status: string;
  responded_at: string | null;
};

export type Approval = {
  approver_id: string;
  display_name: string;
  decision: string;
  comment: string | null;
  created_at: string;
};

export type Loan = {
  id: string;
  user_id: string;
  borrower: string;
  principal: string;
  interest_rate: string;
  interest_method: string;
  term_months: number;
  status: string;
  total_interest: string;
  total_payable: string;
  paid_to_date: string;
  outstanding: string;
  purpose: string;
  requested_at: string;
  approved_at: string | null;
  disbursed_at: string | null;
  guarantors: Guarantor[];
  approvals: Approval[];
};

export type Installment = {
  installment_no: number;
  due_date: string;
  principal_due: string;
  interest_due: string;
  paid_amount: string;
  total_due: string;
  paid_at: string | null;
};

export type Fine = {
  id: string;
  user_id: string;
  member: string;
  fine_type: string;
  amount: string;
  reason: string;
  status: string;
  period_label: string | null;
  assessed_on: string;
  waive_reason: string | null;
  paid: boolean;
  created_at: string;
};

export type DashboardReport = {
  group: {
    name: string;
    currency: string;
    contribution_amount: string;
    contribution_frequency: string;
  };
  period: { label: string; start: string; end: string };
  kpis: {
    collected: string;
    outstanding_loans: string;
    unpaid_fines: string;
    savings: string;
    welfare_balance: string;
    active_members: number;
    pending_loans: number;
  };
  cashflow: Array<{ bucket: string; inflow: string; outflow: string }>;
};

export type LoanBookRow = {
  id: string;
  user_id: string;
  borrower: string;
  status: string;
  principal: string;
  total_payable: string;
  paid: string;
  outstanding: string;
  requested_at: string;
  next_due: string;
};

export type DefaulterRow = {
  loan_id: string;
  user_id: string;
  borrower: string;
  status: string;
  oldest_due: string;
  amount_due: string;
  days_overdue: number;
};

export type ReportFineRow = {
  id: string;
  user_id: string;
  member: string;
  fine_type: string;
  amount: string;
  status: string;
  period_label: string;
  assessed_on: string;
  reason: string;
};

export type ReportJob = {
  id: string;
  report_code: string;
  format: 'csv' | 'pdf';
  status: string;
  file_name: string;
  content_type: string;
  row_count: number;
  created_at: string;
  finished_at: string | null;
  error?: string;
};

export type AuditEntry = {
  id: string;
  actor: string;
  action: string;
  entity_type: string;
  entity_public_id?: string;
  before: unknown;
  after: unknown;
  created_at: string;
};

export type MyRotation = {
  group_id: string;
  group_name: string;
  cycle_id: string;
  cycle_name: string;
  position: number;
  payout_date: string;
  paid: boolean;
};

export type NotificationItem = {
  id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  read_at: string | null;
  created_at: string;
};
