#!/usr/bin/env bash
# End-to-end check of Phase 4: fines and loans against a running server.
# Seed rows are written straight to Postgres so the loan engine has savings to
# borrow against; every behaviour under test still goes through the API.
set -uo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
API="$BASE/api/v1"
PSQL_URL="${DATABASE_URL:-postgres://postgres@localhost:5544/chama?sslmode=disable}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

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
seed_savings() {
  local uid="$1" amount="$2"
  psql "$PSQL_URL" -qtAX -c "INSERT INTO transactions (group_id, user_id, transaction_type_id, status_id, channel_id, amount, narration, completed_at) SELECT (SELECT id FROM groups WHERE public_id = '$GROUP'), u.id, (SELECT id FROM transaction_types WHERE code = 'contribution'), (SELECT id FROM transaction_statuses WHERE code = 'completed'), (SELECT id FROM payment_channels WHERE code = 'cash'), $amount, 'e2e savings seed', now() FROM users u WHERE u.public_id = '$uid'" >/dev/null
}

SUFFIX=$(printf '%06d' $((RANDOM % 1000000)))
register "07${SUFFIX}21" "Admin" "Four"; ADMIN="$ACCESS"; ADMIN_ID="$USER_ID"
register "07${SUFFIX}22" "Borrower" "Five"; BORROWER="$ACCESS"; BORROWER_ID="$USER_ID"
register "07${SUFFIX}23" "Guarantor" "Six"; G1="$ACCESS"; G1_ID="$USER_ID"
register "07${SUFFIX}24" "Guarantor" "Seven"; G2="$ACCESS"; G2_ID="$USER_ID"

echo "== setup =="
status=$(call POST /groups '{"name":"Loans Chama","contribution_amount":"1000.00","contribution_frequency":"monthly"}' "$ADMIN")
expect "$status" 201 "chama created"
GROUP=$(body | jget id)
INVITE=$(body | jget invite_code)
for pair in "$BORROWER:$BORROWER_ID" "$G1:$G1_ID" "$G2:$G2_ID"; do
  token="${pair%%:*}"; uid="${pair##*:}"
  call POST /groups/join "{\"invite_code\":\"$INVITE\"}" "$token" >/dev/null
  call PATCH "/groups/$GROUP/members/$uid" '{"status":"active"}' "$ADMIN" >/dev/null
done
status=$(call PUT "/groups/$GROUP/loans/settings" '{"interest_rate":"10.000","interest_method":"flat","max_multiple_of_savings":"3.00","max_term_months":12,"guarantors_required":1,"allow_loans":true}' "$ADMIN")
expect "$status" 200 "loan settings saved"
status=$(call PUT "/groups/$GROUP/fines/rules/late_contribution" '{"calculation_method":"flat","amount_or_rate":"100.00","grace_days":0}' "$ADMIN")
expect "$status" 200 "late contribution rule saved"

seed_savings "$BORROWER_ID" 50000
seed_savings "$G1_ID" 50000
seed_savings "$G2_ID" 1000
echo "PASS  savings fixtures seeded"

echo "== loan application =="
BSTEP=$(stepup "$BORROWER")
expect_not_empty "$BSTEP" "borrower step-up token"
status=$(call POST "/groups/$GROUP/loans" '{"amount":"3000.00","term_months":3,"purpose":"School fees","guarantors":[]}' "$BORROWER" -H "X-Step-Up-Token: $BSTEP")
expect "$status" 400 "guarantor count enforced"

status=$(call POST "/groups/$GROUP/loans" "{\"amount\":\"3000.00\",\"term_months\":3,\"purpose\":\"School fees\",\"guarantors\":[{\"user_id\":\"$G1_ID\",\"amount\":\"3000.00\"}]}" "$BORROWER" -H "X-Step-Up-Token: $BSTEP")
expect "$status" 201 "loan applied"
LOAN=$(body | jget id)
expect "$(body | jget status)" "pending_guarantors" "loan waits for guarantor"
expect "$(body | jget total_interest)" "900.00" "flat interest computed"
expect "$(body | jget total_payable)" "3900.00" "total payable computed"

status=$(call POST "/groups/$GROUP/loans/$LOAN/decision" '{"decision":"approved"}' "$ADMIN")
expect "$status" 409 "approval blocked while guarantors pending"

echo "== guarantor and approval =="
status=$(call POST "/groups/$GROUP/loans/$LOAN/guarantors/respond" '{"decision":"accepted"}' "$G1")
expect "$status" 200 "guarantor accepts"
expect "$(body | jget status)" "pending_approval" "loan moves to approval queue"

status=$(call POST "/groups/$GROUP/loans/$LOAN/decision" '{"decision":"approved","comment":"Committee approved"}' "$ADMIN")
expect "$status" 200 "committee approves"
expect "$(body | jget status)" "approved" "loan approved"
expect_not_empty "$(body | jget approved_at)" "approved_at recorded"

status=$(call GET "/groups/$GROUP/loans/$LOAN/schedule" "" "$BORROWER")
expect "$status" 200 "schedule readable"
cp "$TMP/body" "$TMP/schedule.json"
SUMS=$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const d=JSON.parse(s).data;const c=x=>Math.round(parseFloat(x)*100);console.log(d.length+" "+d.reduce((a,r)=>a+c(r.principal_due),0)+" "+d.reduce((a,r)=>a+c(r.interest_due),0))})')
expect "$SUMS" "3 300000 90000" "persisted schedule sums exact"

echo "== disbursement and repayment =="
ADSTEP=$(stepup "$ADMIN")
status=$(call POST "/groups/$GROUP/loans/$LOAN/disburse" '{"channel":"cash"}' "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 200 "loan disbursed"
expect "$(body | jget status)" "active" "loan active after disbursement"

REPAY=$(node -e 'const d=require(process.argv[1]).data;const c=x=>Math.round(parseFloat(x)*100);const amount=c(d[0].total_due)+Math.floor(c(d[1].total_due)/2);console.log((amount/100).toFixed(2))' "$TMP/schedule.json")
status=$(call POST "/groups/$GROUP/loans/$LOAN/repayments" "{\"amount\":\"$REPAY\",\"channel\":\"cash\"}" "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 201 "repayment spanning installments recorded"

status=$(call GET "/groups/$GROUP/loans/$LOAN/schedule" "" "$BORROWER")
ALLOC=$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const d=JSON.parse(s).data;const c=x=>Math.round(parseFloat(x)*100);console.log((c(d[0].paid_amount)===c(d[0].total_due))+" "+(c(d[1].paid_amount)>0&&c(d[1].paid_amount)<c(d[1].total_due))+" "+(c(d[2].paid_amount)===0))})')
expect "$ALLOC" "true true true" "oldest-first allocation across installments"

status=$(call POST "/groups/$GROUP/loans/$LOAN/repayments" '{"amount":"99999.00","channel":"cash"}' "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 422 "overpayment rejected"

echo "== default detection =="
psql "$PSQL_URL" -qtAX -c "UPDATE loan_schedule_items SET due_date = CURRENT_DATE - 31 WHERE loan_id = (SELECT id FROM loans WHERE public_id = '$LOAN') AND installment_no = 3" >/dev/null
status=$(call POST "/groups/$GROUP/loans/defaults/run" "" "$ADMIN")
expect "$status" 200 "default scan runs"
expect "$(body | jget marked_defaulted)" "1" "overdue loan marked defaulted"
status=$(call GET "/groups/$GROUP/loans/$LOAN" "" "$ADMIN")
expect "$(body | jget status)" "defaulted" "loan status is defaulted"

echo "== guarantor cover =="
status=$(call POST "/groups/$GROUP/loans" "{\"amount\":\"3000.00\",\"term_months\":3,\"purpose\":\"Over-commit\",\"guarantors\":[{\"user_id\":\"$G2_ID\",\"amount\":\"3000.00\"}]}" "$BORROWER" -H "X-Step-Up-Token: $BSTEP")
expect "$status" 422 "guarantor over-commit rejected"
expect "$(body | jget error.code)" "guarantor_cover_exceeded" "cover error code"

echo "== fine evaluation =="
status=$(call POST "/groups/$GROUP/fines/evaluate" "" "$ADMIN")
expect "$status" 200 "fine evaluation runs"
expect "$(body | jget fines_created)" "4" "one fine per active member"
COUNT=$(psql "$PSQL_URL" -qtAX -c "SELECT count(*) FROM fines WHERE group_id = (SELECT id FROM groups WHERE public_id = '$GROUP') AND period_label IS NOT NULL" | tr -d '[:space:]')
expect "$COUNT" "4" "fine rows persisted"
status=$(call POST "/groups/$GROUP/fines/evaluate" "" "$ADMIN")
expect "$status" 200 "second evaluation runs"
expect "$(body | jget fines_created)" "0" "second evaluation creates nothing"
COUNT=$(psql "$PSQL_URL" -qtAX -c "SELECT count(*) FROM fines WHERE group_id = (SELECT id FROM groups WHERE public_id = '$GROUP') AND period_label IS NOT NULL" | tr -d '[:space:]')
expect "$COUNT" "4" "fine job is idempotent"

echo "== custom fines, waive, manual pay =="
status=$(call POST "/groups/$GROUP/fines" "{\"user_id\":\"$BORROWER_ID\",\"amount\":\"200.00\",\"reason\":\"Missed meeting\"}" "$ADMIN")
expect "$status" 201 "custom fine charged"
FINE_WAIVE=$(body | jget id)
status=$(call POST "/groups/$GROUP/fines/$FINE_WAIVE/waive" '{"reason":"First offence"}' "$ADMIN")
expect "$status" 200 "fine waived"
expect "$(body | jget status)" "waived" "waived status recorded"
expect "$(body | jget waive_reason)" "First offence" "waive reason stored"

status=$(call POST "/groups/$GROUP/fines" "{\"user_id\":\"$BORROWER_ID\",\"amount\":\"300.00\",\"reason\":\"Late fees\"}" "$ADMIN")
expect "$status" 201 "second custom fine charged"
FINE_PAY=$(body | jget id)
status=$(call POST "/groups/$GROUP/fines/$FINE_PAY/pay" '{"amount":"300.00","channel":"cash"}' "$ADMIN" -H "X-Step-Up-Token: $ADSTEP")
expect "$status" 201 "manual fine payment recorded"
expect "$(body | jget fine.status)" "paid" "fine marked paid"
expect_not_empty "$(body | jget transaction_id)" "ledger transaction linked"
status=$(call GET "/groups/$GROUP/fines/$FINE_PAY" "" "$ADMIN")
expect "$(body | jget paid)" "true" "fine detail shows paid"

echo
if [ "$fails" -eq 0 ]; then echo "phase4 e2e: all checks passed"; else echo "phase4 e2e: $fails check(s) failed"; fi
exit "$fails"
