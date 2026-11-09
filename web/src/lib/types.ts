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
  status: 'pending' | 'completed' | 'failed' | 'reversed';
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
