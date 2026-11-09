-- Lookups that the feature modules need beyond the original list.

CREATE TABLE fine_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE approval_decisions (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE rotation_ordering_modes (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE rotation_proposal_statuses (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE vote_choices (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE daraja_environments (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE device_platforms (
    id SMALLINT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO fine_statuses (id, code, name, description, sort_order) VALUES
    (1, 'unpaid', 'Unpaid', 'Still owed by the member', 10),
    (2, 'paid', 'Paid', 'Settled', 20),
    (3, 'waived', 'Waived', 'Forgiven by the committee', 30);

INSERT INTO approval_decisions (id, code, name, description, sort_order) VALUES
    (1, 'approved', 'Approved', 'Accepted the request', 10),
    (2, 'rejected', 'Rejected', 'Declined the request', 20);

INSERT INTO rotation_ordering_modes (id, code, name, description, sort_order) VALUES
    (1, 'random', 'Random draw', 'Verifiable random order', 10),
    (2, 'manual', 'Manual order', 'Committee sets the order', 20),
    (3, 'vote', 'Member vote', 'Members vote on the proposed order', 30);

INSERT INTO rotation_proposal_statuses (id, code, name, description, sort_order) VALUES
    (1, 'open', 'Open', 'Accepting votes', 10),
    (2, 'passed', 'Passed', 'Quorum met and approved', 20),
    (3, 'rejected', 'Rejected', 'Did not carry', 30),
    (4, 'cancelled', 'Cancelled', 'Withdrawn before the deadline', 40);

INSERT INTO vote_choices (id, code, name, description, sort_order) VALUES
    (1, 'for', 'For', 'Supports the proposal', 10),
    (2, 'against', 'Against', 'Opposes the proposal', 20),
    (3, 'abstain', 'Abstain', 'Counts for quorum only', 30);

INSERT INTO daraja_environments (id, code, name, description, sort_order) VALUES
    (1, 'sandbox', 'Sandbox', 'Safaricom test environment', 10),
    (2, 'production', 'Production', 'Live M-Pesa', 20);

INSERT INTO device_platforms (id, code, name, description, sort_order) VALUES
    (1, 'android', 'Android', 'Android app', 10),
    (2, 'ios', 'iOS', 'iPhone app', 20),
    (3, 'web', 'Web', 'Browser session', 30);
