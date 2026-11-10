-- Rotation cycles, slots, order proposals and changeable votes.

-- name: ListRotationCycles :many
SELECT rc.id, rc.public_id, rc.name, rcs.code AS status, rom.code AS ordering_mode,
       (round(rc.contribution_amount * 100))::bigint AS contribution_cents,
       rc.starts_on::text AS starts_on, rc.member_count, rc.draw_seed,
       rc.created_at, rc.completed_at,
       (SELECT count(*)::int FROM rotation_slots rs WHERE rs.cycle_id = rc.id) AS slot_count,
       (SELECT count(*)::int FROM rotation_slots rs
        WHERE rs.cycle_id = rc.id AND rs.payout_transaction_id IS NOT NULL) AS paid_count
FROM rotation_cycles rc
JOIN rotation_cycle_statuses rcs ON rcs.id = rc.status_id
JOIN rotation_ordering_modes rom ON rom.id = rc.ordering_mode_id
WHERE rc.group_id = sqlc.arg(group_id)
ORDER BY rc.created_at DESC, rc.id DESC
LIMIT sqlc.arg(row_limit);

-- name: GetRotationCycle :one
SELECT rc.id, rc.public_id, rc.name, rcs.code AS status, rom.code AS ordering_mode,
       (round(rc.contribution_amount * 100))::bigint AS contribution_cents,
       rc.starts_on::text AS starts_on, rc.member_count, rc.draw_seed,
       rc.created_at, rc.completed_at,
       (SELECT count(*)::int FROM rotation_slots rs WHERE rs.cycle_id = rc.id) AS slot_count,
       (SELECT count(*)::int FROM rotation_slots rs
        WHERE rs.cycle_id = rc.id AND rs.payout_transaction_id IS NOT NULL) AS paid_count
FROM rotation_cycles rc
JOIN rotation_cycle_statuses rcs ON rcs.id = rc.status_id
JOIN rotation_ordering_modes rom ON rom.id = rc.ordering_mode_id
WHERE rc.group_id = sqlc.arg(group_id) AND rc.public_id = sqlc.arg(public_id);

-- name: CreateRotationCycle :one
INSERT INTO rotation_cycles (
    group_id, name, status_id, ordering_mode_id, contribution_amount,
    starts_on, member_count, created_by
) VALUES (
    sqlc.arg(group_id), sqlc.arg(name),
    (SELECT rcs.id FROM rotation_cycle_statuses rcs WHERE rcs.code = 'draft'),
    (SELECT rom.id FROM rotation_ordering_modes rom WHERE rom.code = sqlc.arg(ordering_mode)),
    (sqlc.arg(contribution_cents)::bigint / 100.0)::numeric(15,2),
    sqlc.arg(starts_on)::text::date,
    (SELECT count(*)::smallint FROM group_members gm
     JOIN member_statuses ms ON ms.id = gm.status_id
     WHERE gm.group_id = sqlc.arg(group_id) AND ms.code = 'active'),
    sqlc.arg(created_by)
)
RETURNING id, public_id;

-- name: GetRotationCycleForUpdate :one
SELECT rc.id, rc.public_id, rc.name, rcs.code AS status, rom.code AS ordering_mode,
       (round(rc.contribution_amount * 100))::bigint AS contribution_cents,
       rc.starts_on::text AS starts_on, rc.member_count
FROM rotation_cycles rc
JOIN rotation_cycle_statuses rcs ON rcs.id = rc.status_id
JOIN rotation_ordering_modes rom ON rom.id = rc.ordering_mode_id
WHERE rc.group_id = sqlc.arg(group_id) AND rc.public_id = sqlc.arg(public_id)
FOR UPDATE OF rc;

-- name: GetRotationCycleByIDForUpdate :one
SELECT rc.id, rc.public_id, rc.name, rcs.code AS status, rom.code AS ordering_mode,
       (round(rc.contribution_amount * 100))::bigint AS contribution_cents,
       rc.starts_on::text AS starts_on, rc.member_count
FROM rotation_cycles rc
JOIN rotation_cycle_statuses rcs ON rcs.id = rc.status_id
JOIN rotation_ordering_modes rom ON rom.id = rc.ordering_mode_id
WHERE rc.group_id = sqlc.arg(group_id) AND rc.id = sqlc.arg(cycle_id)
FOR UPDATE OF rc;

-- name: UpdateRotationCycleStatus :execrows
UPDATE rotation_cycles rc
SET status_id = (SELECT rcs.id FROM rotation_cycle_statuses rcs WHERE rcs.code = sqlc.arg(status)),
    completed_at = CASE WHEN sqlc.arg(status)::text = 'completed' THEN now() ELSE rc.completed_at END
WHERE rc.id = sqlc.arg(cycle_id) AND rc.group_id = sqlc.arg(group_id)
  AND status_id = (SELECT rcs.id FROM rotation_cycle_statuses rcs WHERE rcs.code = sqlc.arg(expected_status));

-- name: SetRotationDrawSeed :exec
UPDATE rotation_cycles SET draw_seed = sqlc.arg(draw_seed)
WHERE id = sqlc.arg(cycle_id) AND group_id = sqlc.arg(group_id);

-- name: GetRotationMembers :many
SELECT gm.user_id, u.public_id AS user_public_id, u.first_name, u.last_name
FROM group_members gm
JOIN users u ON u.id = gm.user_id
JOIN member_statuses ms ON ms.id = gm.status_id
WHERE gm.group_id = sqlc.arg(group_id) AND ms.code = 'active'
ORDER BY gm.joined_at NULLS LAST, gm.id;

-- name: GetGroupFrequency :one
SELECT cf.code AS frequency
FROM groups g JOIN contribution_frequencies cf ON cf.id = g.contribution_frequency_id
WHERE g.id = sqlc.arg(group_id);

-- name: AddRotationSlot :one
INSERT INTO rotation_slots (group_id, cycle_id, member_id, position, payout_date)
VALUES (
    sqlc.arg(group_id), sqlc.arg(cycle_id), sqlc.arg(member_id), sqlc.arg(position),
    sqlc.arg(payout_date)::text::date
)
RETURNING id, public_id;

-- name: ListRotationSlots :many
SELECT rs.public_id, u.public_id AS user_public_id, u.first_name, u.last_name,
       rs.position, rs.payout_date::text AS payout_date,
       pt.public_id AS payout_transaction_public_id
FROM rotation_slots rs
JOIN users u ON u.id = rs.member_id
LEFT JOIN transactions pt ON pt.id = rs.payout_transaction_id
WHERE rs.group_id = sqlc.arg(group_id) AND rs.cycle_id = sqlc.arg(cycle_id)
ORDER BY rs.position;

-- name: ListRotationSlotsForUpdate :many
SELECT rs.id, rs.public_id, rs.member_id, rs.position, rs.payout_date::text AS payout_date,
       rs.payout_transaction_id
FROM rotation_slots rs
WHERE rs.group_id = sqlc.arg(group_id) AND rs.cycle_id = sqlc.arg(cycle_id)
ORDER BY rs.position
FOR UPDATE OF rs;

-- name: GetRotationSlot :one
SELECT rs.id, rs.public_id, rs.member_id, rs.position, rs.payout_date::text AS payout_date,
       rs.payout_transaction_id, rc.public_id AS cycle_public_id, rcs.code AS cycle_status
FROM rotation_slots rs
JOIN rotation_cycles rc ON rc.id = rs.cycle_id
JOIN rotation_cycle_statuses rcs ON rcs.id = rc.status_id
WHERE rs.group_id = sqlc.arg(group_id) AND rs.public_id = sqlc.arg(public_id);

-- name: MarkRotationSlotPaid :execrows
UPDATE rotation_slots SET payout_transaction_id = sqlc.arg(payout_transaction_id)
WHERE id = sqlc.arg(slot_id) AND group_id = sqlc.arg(group_id)
  AND payout_transaction_id IS NULL;

-- name: CountRotationSlots :one
SELECT count(*)::int AS total,
       count(*) FILTER (WHERE payout_transaction_id IS NOT NULL)::int AS paid
FROM rotation_slots WHERE group_id = sqlc.arg(group_id) AND cycle_id = sqlc.arg(cycle_id);

-- name: CreateRotationProposal :one
INSERT INTO rotation_proposals (
    group_id, cycle_id, proposed_by, status_id, quorum_percent, eligible_members, closes_at
) VALUES (
    sqlc.arg(group_id), sqlc.arg(cycle_id), sqlc.arg(proposed_by),
    (SELECT rps.id FROM rotation_proposal_statuses rps WHERE rps.code = 'open'),
    sqlc.arg(quorum_percent),
    (SELECT count(*)::smallint FROM group_members gm
     JOIN member_statuses ms ON ms.id = gm.status_id
     WHERE gm.group_id = sqlc.arg(group_id) AND ms.code = 'active'),
    sqlc.arg(closes_at)::timestamptz
)
RETURNING id, public_id, eligible_members;

-- name: AddRotationProposalSlot :exec
INSERT INTO rotation_proposal_slots (proposal_id, group_id, position, member_id)
VALUES (sqlc.arg(proposal_id), sqlc.arg(group_id), sqlc.arg(position), sqlc.arg(member_id));

-- name: ListRotationProposals :many
SELECT rp.public_id, rps.code AS status, rp.quorum_percent, rp.eligible_members,
       rp.opens_at, rp.closes_at, rp.closed_at, rp.created_at,
       (count(rv.id) FILTER (WHERE vc.code = 'for'))::int AS for_count,
       (count(rv.id) FILTER (WHERE vc.code = 'against'))::int AS against_count,
       (count(rv.id) FILTER (WHERE vc.code = 'abstain'))::int AS abstain_count,
       count(rv.id)::int AS total_count
FROM rotation_proposals rp
JOIN rotation_proposal_statuses rps ON rps.id = rp.status_id
LEFT JOIN rotation_votes rv ON rv.proposal_id = rp.id
LEFT JOIN vote_choices vc ON vc.id = rv.choice_id
WHERE rp.group_id = sqlc.arg(group_id)
  AND rp.cycle_id = (SELECT rc.id FROM rotation_cycles rc
                     WHERE rc.public_id = sqlc.arg(cycle_public_id) AND rc.group_id = sqlc.arg(group_id))
GROUP BY rp.public_id, rps.code, rp.quorum_percent, rp.eligible_members,
         rp.opens_at, rp.closes_at, rp.closed_at, rp.created_at
ORDER BY rp.created_at DESC
LIMIT sqlc.arg(row_limit);

-- name: GetRotationProposal :one
SELECT rp.id, rp.public_id, rp.cycle_id, rc.public_id AS cycle_public_id,
       rp.status_id, rps.code AS status, u.public_id AS proposed_by_public_id,
       u.first_name AS proposed_by_first_name, u.last_name AS proposed_by_last_name,
       rp.quorum_percent, rp.eligible_members, rp.opens_at, rp.closes_at, rp.closed_at,
       rp.result
FROM rotation_proposals rp
JOIN rotation_proposal_statuses rps ON rps.id = rp.status_id
JOIN rotation_cycles rc ON rc.id = rp.cycle_id
JOIN users u ON u.id = rp.proposed_by
WHERE rp.group_id = sqlc.arg(group_id) AND rp.public_id = sqlc.arg(public_id);

-- name: GetRotationProposalForUpdate :one
SELECT rp.id, rp.public_id, rp.cycle_id, rp.status_id, rps.code AS status,
       rp.quorum_percent, rp.eligible_members, rp.opens_at, rp.closes_at, rp.closed_at
FROM rotation_proposals rp
JOIN rotation_proposal_statuses rps ON rps.id = rp.status_id
WHERE rp.group_id = sqlc.arg(group_id) AND rp.public_id = sqlc.arg(public_id)
FOR UPDATE OF rp;

-- name: ListRotationProposalSlots :many
SELECT rps.position, u.public_id AS user_public_id, u.first_name, u.last_name
FROM rotation_proposal_slots rps
JOIN users u ON u.id = rps.member_id
WHERE rps.group_id = sqlc.arg(group_id) AND rps.proposal_id = sqlc.arg(proposal_id)
ORDER BY rps.position;

-- name: ListRotationProposalMemberIDs :many
SELECT position, member_id FROM rotation_proposal_slots
WHERE group_id = sqlc.arg(group_id) AND proposal_id = sqlc.arg(proposal_id)
ORDER BY position;

-- name: UpsertRotationVote :exec
INSERT INTO rotation_votes (group_id, proposal_id, member_id, choice_id)
VALUES (
    sqlc.arg(group_id), sqlc.arg(proposal_id), sqlc.arg(member_id),
    (SELECT vc.id FROM vote_choices vc WHERE vc.code = sqlc.arg(choice))
)
ON CONFLICT (proposal_id, member_id) DO UPDATE
SET choice_id = EXCLUDED.choice_id, cast_at = now();

-- name: GetRotationVote :one
SELECT vc.code AS choice, rv.cast_at
FROM rotation_votes rv JOIN vote_choices vc ON vc.id = rv.choice_id
WHERE rv.proposal_id = sqlc.arg(proposal_id) AND rv.member_id = sqlc.arg(member_id);

-- name: TallyRotationVotes :one
SELECT count(*) FILTER (WHERE vc.code = 'for')::int AS for_count,
       count(*) FILTER (WHERE vc.code = 'against')::int AS against_count,
       count(*) FILTER (WHERE vc.code = 'abstain')::int AS abstain_count,
       count(*)::int AS total_count
FROM rotation_votes rv
JOIN vote_choices vc ON vc.id = rv.choice_id
WHERE rv.proposal_id = sqlc.arg(proposal_id);

-- name: CloseRotationProposal :execrows
UPDATE rotation_proposals rp
SET status_id = (SELECT rps.id FROM rotation_proposal_statuses rps WHERE rps.code = sqlc.arg(status)),
    closed_at = now(), result = sqlc.arg(result)::jsonb
WHERE rp.id = sqlc.arg(proposal_id) AND rp.group_id = sqlc.arg(group_id) AND rp.closed_at IS NULL;

-- name: ListExpiredRotationProposals :many
SELECT rp.id, rp.public_id, rp.group_id, rp.cycle_id
FROM rotation_proposals rp
JOIN rotation_proposal_statuses rps ON rps.id = rp.status_id
WHERE rps.code = 'open' AND rp.closes_at <= now()
ORDER BY rp.closes_at
LIMIT sqlc.arg(row_limit);

-- name: ListMyRotation :many
SELECT g.public_id AS group_public_id, g.name AS group_name, rc.public_id AS cycle_public_id,
       rc.name AS cycle_name, rs.position, rs.payout_date::text AS payout_date,
       (rs.payout_transaction_id IS NOT NULL)::boolean AS paid
FROM rotation_slots rs
JOIN rotation_cycles rc ON rc.id = rs.cycle_id
JOIN groups g ON g.id = rs.group_id
WHERE rs.member_id = sqlc.arg(user_id)
ORDER BY rs.payout_date DESC, rs.id DESC
LIMIT sqlc.arg(row_limit);
