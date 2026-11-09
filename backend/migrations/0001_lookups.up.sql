-- Lookup tables: every status, type, role and channel is a table, never an enum.
-- Ids are explicit and stable so seeds and Go constants agree across environments.

CREATE TABLE member_roles (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE member_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE contribution_frequencies (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE transaction_types (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE transaction_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE payment_channels (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE payment_shortcode_types (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE loan_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE guarantor_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE fine_types (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE fine_calculation_methods (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE interest_methods (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE welfare_claim_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE rotation_cycle_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE notification_types (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE otp_purposes (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE report_job_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO member_roles (id, code, name, description, sort_order) VALUES
    (1, 'admin', 'Admin', 'Full control of the chama', 10),
    (2, 'treasurer', 'Treasurer', 'Records payments and runs the ledger', 20),
    (3, 'secretary', 'Secretary', 'Maintains member records and reads reports', 30),
    (4, 'member', 'Member', 'Contributes, borrows and votes', 40);

INSERT INTO member_statuses (id, code, name, description, sort_order) VALUES
    (1, 'pending', 'Pending', 'Awaiting admin approval', 10),
    (2, 'active', 'Active', 'Full member', 20),
    (3, 'suspended', 'Suspended', 'Temporarily barred from new activity', 30),
    (4, 'exited', 'Exited', 'Left the chama', 40);

INSERT INTO contribution_frequencies (id, code, name, description, sort_order) VALUES
    (1, 'weekly', 'Weekly', 'Every week', 10),
    (2, 'biweekly', 'Every two weeks', 'Fortnightly', 20),
    (3, 'monthly', 'Monthly', 'Once a month', 30),
    (4, 'quarterly', 'Quarterly', 'Every three months', 40);

INSERT INTO transaction_types (id, code, name, description, sort_order) VALUES
    (1, 'contribution', 'Contribution', 'Member savings contribution', 10),
    (2, 'fine', 'Fine', 'Fine charged or paid', 20),
    (3, 'loan_disbursement', 'Loan disbursement', 'Money paid out to a borrower', 30),
    (4, 'loan_repayment', 'Loan repayment', 'Borrower repays principal and interest', 40),
    (5, 'welfare_contribution', 'Welfare contribution', 'Member pays into the welfare fund', 50),
    (6, 'welfare_payout', 'Welfare payout', 'Fund pays a claim', 60),
    (7, 'rotation_payout', 'Rotation payout', 'Merry-go-round payout to a member', 70),
    (8, 'adjustment', 'Adjustment', 'Manual correction with a reason', 80),
    (9, 'reversal', 'Reversal', 'Mirror row that cancels an earlier entry', 90);

INSERT INTO transaction_statuses (id, code, name, description, sort_order) VALUES
    (1, 'pending', 'Pending', 'Awaiting provider confirmation', 10),
    (2, 'completed', 'Completed', 'Settled and part of the ledger', 20),
    (3, 'failed', 'Failed', 'Provider or validation rejected it', 30),
    (4, 'cancelled', 'Cancelled', 'Cancelled before settlement', 40),
    (5, 'reversed', 'Reversed', 'Superseded by a reversal row', 50);

INSERT INTO payment_channels (id, code, name, description, sort_order) VALUES
    (1, 'mpesa_stk', 'M-Pesa STK Push', 'Prompt sent to the payer phone', 10),
    (2, 'mpesa_manual', 'M-Pesa manual', 'Treasurer records an M-Pesa receipt', 20),
    (3, 'cash', 'Cash', 'Cash handed to the treasurer', 30),
    (4, 'bank_transfer', 'Bank transfer', 'Deposit or transfer into the group account', 40),
    (5, 'other', 'Other', 'Any other channel', 50);

INSERT INTO payment_shortcode_types (id, code, name, description, sort_order) VALUES
    (1, 'paybill', 'Paybill', 'Business number plus account reference', 10),
    (2, 'till', 'Buy Goods (Till)', 'Lipa na M-Pesa till number', 20);

INSERT INTO loan_statuses (id, code, name, description, sort_order) VALUES
    (1, 'pending_guarantors', 'Waiting for guarantors', 'Guarantors have not all responded', 10),
    (2, 'pending_approval', 'Waiting for approval', 'Ready for the committee', 20),
    (3, 'approved', 'Approved', 'Approved, not yet disbursed', 30),
    (4, 'rejected', 'Rejected', 'Declined by the committee', 40),
    (5, 'active', 'Active', 'Disbursed and being repaid', 50),
    (6, 'fully_paid', 'Fully paid', 'No outstanding balance', 60),
    (7, 'defaulted', 'Defaulted', 'Overdue beyond the group policy', 70),
    (8, 'written_off', 'Written off', 'Committee wrote off the balance', 80);

INSERT INTO guarantor_statuses (id, code, name, description, sort_order) VALUES
    (1, 'pending', 'Pending', 'Invited, no answer yet', 10),
    (2, 'accepted', 'Accepted', 'Guarantor accepted the request', 20),
    (3, 'declined', 'Declined', 'Guarantor declined', 30);

INSERT INTO fine_types (id, code, name, description, sort_order) VALUES
    (1, 'late_contribution', 'Late contribution', 'Contribution paid after the due date', 10),
    (2, 'late_loan_repayment', 'Late loan repayment', 'Installment paid late', 20),
    (3, 'absence', 'Absence', 'Missed a required meeting', 30),
    (4, 'custom', 'Custom fine', 'Any other offence defined by the group', 40);

INSERT INTO fine_calculation_methods (id, code, name, description, sort_order) VALUES
    (1, 'flat', 'Flat amount', 'A fixed shilling amount', 10),
    (2, 'percentage', 'Percentage', 'A percentage of the amount due', 20);

INSERT INTO interest_methods (id, code, name, description, sort_order) VALUES
    (1, 'flat', 'Flat rate', 'Interest charged on the original principal', 10),
    (2, 'reducing_balance', 'Reducing balance', 'Interest charged on the outstanding balance', 20);

INSERT INTO welfare_claim_statuses (id, code, name, description, sort_order) VALUES
    (1, 'pending', 'Pending', 'Awaiting committee decision', 10),
    (2, 'approved', 'Approved', 'Approved, awaiting payout', 20),
    (3, 'rejected', 'Rejected', 'Claim declined', 30),
    (4, 'paid', 'Paid', 'Payout recorded', 40);

INSERT INTO rotation_cycle_statuses (id, code, name, description, sort_order) VALUES
    (1, 'draft', 'Draft', 'Positions being agreed', 10),
    (2, 'active', 'Active', 'Payouts in progress', 20),
    (3, 'completed', 'Completed', 'Every member has been paid', 30);

INSERT INTO notification_types (id, code, name, description, sort_order) VALUES
    (1, 'contribution_due', 'Contribution due', 'Reminder before a due date', 10),
    (2, 'payment_received', 'Payment received', 'A payment settled', 20),
    (3, 'loan_update', 'Loan update', 'Loan status changed', 30),
    (4, 'guarantor_request', 'Guarantor request', 'A member asked you to guarantee', 40),
    (5, 'fine_applied', 'Fine applied', 'A fine was charged', 50),
    (6, 'rotation_turn', 'Rotation turn', 'Your payout turn is coming', 60),
    (7, 'general', 'General', 'Anything else from the group', 70);

INSERT INTO otp_purposes (id, code, name, description, sort_order) VALUES
    (1, 'login', 'Login', 'Sign in to an existing account', 10),
    (2, 'registration', 'Registration', 'Create a new account', 20),
    (3, 'pin_reset', 'PIN reset', 'Reset the 4-digit PIN', 30);

INSERT INTO report_job_statuses (id, code, name, description, sort_order) VALUES
    (1, 'queued', 'Queued', 'Waiting for a worker', 10),
    (2, 'running', 'Running', 'Being rendered', 20),
    (3, 'done', 'Done', 'Ready to download', 30),
    (4, 'failed', 'Failed', 'Rendering failed', 40);
