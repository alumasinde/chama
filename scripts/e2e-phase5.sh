#!/usr/bin/env bash
# End-to-end check of Phase 5: welfare, rotation/voting and notifications.
set -uo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
API="$BASE/api/v1"
PSQL_URL="${DATABASE_URL:-postgres://postgres@localhost:5544/chama?sslmode=disable}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# Repeated local runs share one loopback IP and would otherwise hit the 10/hour OTP IP throttle.
psql "$PSQL_URL" -q -c "DELETE FROM auth_throttle WHERE key LIKE 'otp:ip:%'" >/dev/null

jget() {
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);let v=j;for(const k of process.argv[1].split("."))v=v==null?undefined:v[k];console.log(v===undefined||v===null?"":String(v))}catch(e){console.log("")}})' "$1"
}
call() {
  local method="$1" path="$2" data="${3:-}" auth="${4:-}" extra=("${@:5}")
  local args=(-s -o "$TMP/body" -w '%{http_code}' -X "$method" "$API$path" -H 'Content-Type: application/json')
  [ -n "$auth" ] && args+=(-H "Authorization: Bearer $auth")
  [ "${#extra[@]}" -gt 0 ] && args+=("${extra[@]}")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}
expect() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then echo "PASS  $label"; else
    echo "FAIL  $label (got '$got', want '$want')"; cat "$TMP/body"; echo; fails=$((fails + 1))
  fi
}
expect_not_empty() {
  if [ -n "$1" ]; then echo "PASS  $2"; else echo "FAIL  $2 (empty)"; fails=$((fails + 1)); fi
}
body() { cat "$TMP/body"; }

register() {
  local phone="$1" first="$2" last="$3"
  call POST /auth/otp/request "{\"phone_number\":\"$phone\",\"purpose\":\"registration\"}" >/dev/null
  local code; code=$(body | jget dev_code)
  call POST /auth/otp/verify "{\"phone_number\":\"$phone\",\"code\":\"$code\",\"purpose\":\"registration\"}" >/dev/null
  local reg; reg=$(body | jget registration_token)
  call POST /auth/register "{\"first_name\":\"$first\",\"last_name\":\"$last\",\"pin\":\"4826\",\"password\":\"ChamaStrong2026\"}" "$reg" >/dev/null
  ACCESS=$(body | jget access_token)
  USER_ID=$(body | jget user.id)
  if [ -z "$ACCESS" ]; then echo "FAIL  register $phone: $(body)"; exit 1; fi
}
stepup() {
  call POST /auth/pin/verify '{"pin":"4826"}' "$1" >/dev/null
  body | jget step_up_token
}

SUFFIX=$(printf '%06d' $((RANDOM % 1000000)))
register "07${SUFFIX}31" "Admin" "Five"; ADMIN="$ACCESS"; ADMIN_ID="$USER_ID"
register "07${SUFFIX}32" "Welfare" "Member"; M1="$ACCESS"; M1_ID="$USER_ID"
register "07${SUFFIX}33" "Rotation" "Member"; M2="$ACCESS"; M2_ID="$USER_ID"
register "07${SUFFIX}34" "Voting" "Member"; M3="$ACCESS"; M3_ID="$USER_ID"

echo "== setup =="
status=$(call POST /groups '{"name":"Welfare Rotation Chama","contribution_amount":"1000.00","contribution_frequency":"monthly"}' "$ADMIN")
expect "$status" 201 "chama created"
GROUP=$(body | jget id)
INVITE=$(body | jget invite_code)
for pair in "$M1:$M1_ID" "$M2:$M2_ID" "$M3:$M3_ID"; do
  token="${pair%%:*}"; uid="${pair##*:}"
  call POST /groups/join "{\"invite_code\":\"$INVITE\"}" "$token" >/dev/null
  call PATCH "/groups/$GROUP/members/$uid" '{"status":"active"}' "$ADMIN" >/dev/null
done
echo "PASS  members activated"
ADSTEP=$(stepup "$ADMIN")
expect_not_empty "$ADSTEP" "admin step-up token"

echo "== welfare =="
status=$(call PUT "/groups/$GROUP/welfare" '{"name":"Welfare fund","monthly_amount":"1000.00","is_active":true}' "$ADMIN")
expect "$status" 200 "welfare fund saved"
expect "$(body | jget configured)" "true" "fund configured"
expect "$(body | jget balance)" "0.00" "fund starts empty"

status=$(call POST "/groups/$GROUP/welfare/contributions" "{\"user_id\":\"$M1_ID\",\"amount\":\"1000.00\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 201 "manual welfare contribution recorded"
expect "$(body | jget amount)" "1000.00" "contribution amount"
status=$(call POST "/groups/$GROUP/welfare/contributions" "{\"user_id\":\"$M1_ID\",\"amount\":\"1000.00\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 409 "duplicate period contribution rejected"
status=$(call GET "/groups/$GROUP/welfare" "" "$ADMIN")
expect "$(body | jget balance)" "1000.00" "fund balance after contribution"

status=$(call POST "/groups/$GROUP/welfare/claims" '{"amount":"400.00","reason":"Medical support"}' "$M1")
expect "$status" 201 "member welfare claim created"
CLAIM=$(body | jget id)
expect "$(body | jget status)" "pending" "claim awaits decision"
status=$(call POST "/groups/$GROUP/welfare/claims/$CLAIM/decision" '{"decision":"approved","comment":"Approved by committee"}' "$ADMIN")
expect "$status" 200 "claim approved"
expect "$(body | jget status)" "approved" "claim status approved"
status=$(call POST "/groups/$GROUP/welfare/claims/$CLAIM/payout" '{"channel":"cash"}' "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 201 "claim payout recorded"
expect "$(body | jget claim.status)" "paid" "claim marked paid"
expect_not_empty "$(body | jget transaction_id)" "payout ledger transaction linked"
status=$(call GET "/groups/$GROUP/welfare" "" "$ADMIN")
expect "$(body | jget balance)" "600.00" "fund balance after payout"
status=$(call POST "/groups/$GROUP/welfare/claims/$CLAIM/payout" '{"channel":"cash"}' "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 409 "paid claim cannot be paid twice"

echo "== rotation voting =="
status=$(call POST "/groups/$GROUP/rotation/cycles" '{"name":"2027 cycle","ordering_mode":"vote","contribution_amount":"1000.00","starts_on":"2026-12-01"}' "$ADMIN")
expect "$status" 201 "vote cycle created"
CYCLE=$(body | jget id)
expect "$(body | jget status)" "draft" "cycle starts as draft"
status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/start" "" "$ADMIN")
expect "$status" 409 "vote cycle cannot start before a vote"

CLOSES=$(node -e 'console.log(new Date(Date.now()+86400000).toISOString())')
SLOTS="[\"$ADMIN_ID\",\"$M1_ID\",\"$M2_ID\",\"$M3_ID\"]"
status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/proposals" "{\"slots\":$SLOTS,\"closes_at\":\"$CLOSES\",\"quorum_percent\":50}" "$ADMIN")
expect "$status" 201 "proposal opened"
PROPOSAL=$(body | jget id)
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL/vote" '{"choice":"for"}' "$M1")
expect "$status" 200 "member votes for"
expect "$(body | jget tally.total)" "1" "first vote counted"
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL/vote" '{"choice":"against"}' "$M1")
expect "$status" 200 "member changes vote"
expect "$(body | jget tally.total)" "1" "changed vote updates instead of duplicating"
expect "$(body | jget tally.against)" "1" "changed vote is against"
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL/vote" '{"choice":"for"}' "$M2")
expect "$status" 200 "second member votes"
expect "$(body | jget tally.total)" "2" "two votes total"
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL/close" "" "$ADMIN")
expect "$status" 200 "proposal closes"
expect "$(body | jget status)" "rejected" "tie fails"
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL/vote" '{"choice":"for"}' "$M3")
expect "$status" 409 "vote after close rejected"

status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/proposals" "{\"slots\":$SLOTS,\"closes_at\":\"$CLOSES\",\"quorum_percent\":50}" "$ADMIN")
expect "$status" 201 "second proposal opened"
PROPOSAL2=$(body | jget id)
call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL2/vote" '{"choice":"for"}' "$M1" >/dev/null
call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL2/vote" '{"choice":"for"}' "$M2" >/dev/null
call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL2/vote" '{"choice":"abstain"}' "$M3" >/dev/null
status=$(call POST "/groups/$GROUP/rotation/proposals/$PROPOSAL2/close" "" "$ADMIN")
expect "$status" 200 "second proposal closes"
expect "$(body | jget status)" "passed" "majority passes"
status=$(call GET "/groups/$GROUP/rotation/cycles/$CYCLE" "" "$ADMIN")
expect "$status" 200 "cycle readable after vote"
expect "$(body | jget status)" "active" "passing vote starts the cycle"
expect "$(body | jget slot_count)" "4" "cycle materialised four slots"

DEDUPE=$(psql "$PSQL_URL" -qtAX -c "SELECT count(*) FROM notifications WHERE dedupe_key = 'rotation:$CYCLE:start:$M1_ID'" | tr -d '[:space:]')
expect "$DEDUPE" "1" "rotation notification created once"

echo "== rotation payouts =="
cp "$TMP/body" "$TMP/cycle.json"
FIRST_SLOT=$(node -e 'const d=require(process.argv[1]);console.log(d.slots[0].id)' "$TMP/cycle.json")
status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/payouts" "{\"slot_id\":\"$FIRST_SLOT\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 201 "first rotation payout recorded"
expect_not_empty "$(body | jget transaction_id)" "rotation payout ledger transaction linked"
status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/payouts" "{\"slot_id\":\"$FIRST_SLOT\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 409 "same slot cannot be paid twice"

for i in 1 2 3; do
  slot=$(node -e 'const d=require(process.argv[1]);console.log(d.slots[Number(process.argv[2])].id)' "$TMP/cycle.json" "$i")
  status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/payouts" "{\"slot_id\":\"$slot\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
  expect "$status" 201 "payout $((i + 1)) recorded"
done
status=$(call GET "/groups/$GROUP/rotation/cycles/$CYCLE" "" "$ADMIN")
expect "$(body | jget status)" "completed" "cycle completes after final payout"
status=$(call POST "/groups/$GROUP/rotation/cycles/$CYCLE/payouts" "{\"slot_id\":\"$FIRST_SLOT\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 409 "completed cycle takes no more payouts"

echo "== cycle start guard =="
status=$(call POST "/groups/$GROUP/rotation/cycles" '{"name":"Random cycle","ordering_mode":"random","contribution_amount":"500.00","starts_on":"2026-12-01"}' "$ADMIN")
expect "$status" 201 "random cycle created"
RANDOM_CYCLE=$(body | jget id)
status=$(call POST "/groups/$GROUP/rotation/cycles/$RANDOM_CYCLE/start" "" "$ADMIN")
expect "$status" 200 "random cycle starts"
expect "$(body | jget status)" "active" "random cycle active"
status=$(call POST "/groups/$GROUP/rotation/cycles/$RANDOM_CYCLE/start" "" "$ADMIN")
expect "$status" 409 "cycle cannot start twice"

echo "== notifications =="
status=$(call GET "/notifications?unread=true&limit=100" "" "$M1")
expect "$status" 200 "notifications listed"
HAS=$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const d=JSON.parse(s).data;console.log(d.some(n=>n.type==="rotation_turn"))})')
expect "$HAS" "true" "rotation turn notification present"
status=$(call POST /notifications/read '{"all":true}' "$M1")
expect "$status" 200 "all notifications marked read"
COUNT=$(body | jget marked_read)
if [ "$COUNT" -ge 1 ]; then echo "PASS  read count returned"; else echo "FAIL  read count returned ($COUNT)"; fails=$((fails + 1)); fi
status=$(call GET "/notifications?unread=true&limit=100" "" "$M1")
expect "$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).data.length)})')" "0" "unread list is empty after marking all"

echo
if [ "$fails" -eq 0 ]; then echo "phase5 e2e: all checks passed"; else echo "phase5 e2e: $fails check(s) failed"; fi
exit "$fails"
