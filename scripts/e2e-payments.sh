#!/usr/bin/env bash
# End-to-end check of Phase 3: STK, step-up, idempotency, callback settlement, receipts.
set -uo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
API="$BASE/api/v1"
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
body() { cat "$TMP/body"; }

register() {
  local phone="$1"
  call POST /auth/otp/request "{\"phone_number\":\"$phone\",\"purpose\":\"registration\"}" >/dev/null
  local code; code=$(body | jget dev_code)
  call POST /auth/otp/verify "{\"phone_number\":\"$phone\",\"code\":\"$code\",\"purpose\":\"registration\"}" >/dev/null
  local reg; reg=$(body | jget registration_token)
  call POST /auth/register "{\"first_name\":\"Amina\",\"last_name\":\"Otieno\",\"pin\":\"4826\",\"password\":\"ChamaStrong2026\"}" "$reg" >/dev/null
  ACCESS=$(body | jget access_token)
  if [ -z "$ACCESS" ]; then echo "FAIL  register $phone: $(body)"; exit 1; fi
}

SUFFIX=$(printf '%06d' $((RANDOM % 1000000)))
register "07${SUFFIX}11"; ADMIN="$ACCESS"
register "07${SUFFIX}12"; OUTSIDER="$ACCESS"

call POST /groups '{"name":"Payments Chama","contribution_amount":"1500.00","contribution_frequency":"monthly"}' "$ADMIN" >/dev/null
GROUP=$(body | jget id)
[ -n "$GROUP" ] && echo "PASS  chama created" || { echo "FAIL  chama creation"; exit 1; }

curl -s -o /dev/null -X PUT "$API/groups/$GROUP/payment-settings" -H 'Content-Type: application/json' -H "Authorization: Bearer $ADMIN" \
  -d '{"shortcode_type":"paybill","shortcode":"247247","daraja_environment":"sandbox","consumer_key":"ck_live_1234567890","consumer_secret":"cs_live_1234567890","passkey":"pk_live_1234567890"}'
CALLBACK_URL=$(curl -s -X PUT "$API/groups/$GROUP/payment-settings" -H 'Content-Type: application/json' -H "Authorization: Bearer $ADMIN" \
  -d '{"shortcode_type":"paybill","shortcode":"247247","daraja_environment":"sandbox"}' | jget callback_url)
CALLBACK_PATH="${CALLBACK_URL#$BASE}"
GOOD_SECRET="${CALLBACK_PATH##*/}"
echo "== settings =="
[ -n "$CALLBACK_PATH" ] && echo "PASS  callback URL issued" || { echo "FAIL  callback URL missing"; fails=$((fails + 1)); }

call POST /auth/pin/verify '{"pin":"4826"}' "$ADMIN" >/dev/null
STEP=$(body | jget step_up_token)
[ -n "$STEP" ] && echo "PASS  step-up token minted" || { echo "FAIL  step-up token"; fails=$((fails + 1)); }

echo "== STK guard rails =="
status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$ADMIN" -H "Idempotency-Key: stk-${SUFFIX}-a")
expect "$status" 403 "STK without step-up rejected"
expect "$(body | jget error.code)" "step_up_required" "step-up error code"

status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$ADMIN" -H "X-Step-Up-Token: $STEP")
expect "$status" 400 "STK without Idempotency-Key rejected"

status=$(curl -s -o "$TMP/body" -w '%{http_code}' -X POST "$API/groups/$GROUP/payments/stk" -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ADMIN" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-b" \
  -d '{"amount":"10.50","purpose":"contribution"}')
expect "$status" 422 "fractional shillings rejected"
expect "$(body | jget error.code)" "amount_not_whole_shillings" "fractional amount code"

status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$OUTSIDER" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-c")
expect "$status" 404 "non-member cannot start STK"

echo "== STK and idempotency =="
status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$ADMIN" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-d")
expect "$status" 202 "STK accepted"
CHECKOUT=$(body | jget checkout_request_id)
PAYREQ=$(body | jget payment_request_id)
[ -n "$CHECKOUT" ] && echo "PASS  checkout request id returned" || { echo "FAIL  checkout id"; fails=$((fails + 1)); }

status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$ADMIN" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-d")
expect "$status" 202 "replay same key accepted"
expect "$(body | jget checkout_request_id)" "$CHECKOUT" "replay returns identical response"

status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"2000.00","purpose":"contribution"}' "$ADMIN" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-d")
expect "$status" 409 "same key different body rejected"
expect "$(body | jget error.code)" "idempotency_conflict" "idempotency conflict code"

echo "== callback =="
BAD_PATH="${CALLBACK_PATH%/*}/wrong-secret"
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE$BAD_PATH" -H 'Content-Type: application/json' -d '{}')
expect "$status" 403 "wrong callback secret rejected"

PAYLOAD=$(printf '{"Body":{"stkCallback":{"MerchantRequestID":"m1","CheckoutRequestID":"%s","ResultCode":0,"ResultDesc":"The service request is processed successfully.","CallbackMetadata":{"Item":[{"Name":"Amount","Value":1500},{"Name":"MpesaReceiptNumber","Value":"QK12345678"}]}}}}' "$CHECKOUT")
status=$(curl -s -o "$TMP/body" -w '%{http_code}' -X POST "$BASE$CALLBACK_PATH" -H 'Content-Type: application/json' -d "$PAYLOAD")
expect "$status" 200 "callback accepted"
expect "$(body | jget ResultCode)" "0" "callback acknowledgement"
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE$CALLBACK_PATH" -H 'Content-Type: application/json' -d "$PAYLOAD")
expect "$status" 200 "duplicate callback accepted"

status=$(call GET "/groups/$GROUP/transactions" "" "$ADMIN")
expect "$status" 200 "transactions list"
COUNT=$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.data.length)})')
expect "$COUNT" "1" "exactly one ledger row after duplicate callback"
expect "$(body | jget data.0.status)" "completed" "transaction completed"
expect "$(body | jget data.0.amount)" "1500.00" "amount recorded"
expect "$(body | jget data.0.reference_code)" "QK12345678" "receipt stored"
TX=$(body | jget data.0.id)
status=$(call GET "/groups/$GROUP/transactions/$TX" "" "$ADMIN")
expect "$status" 200 "receipt detail"
expect "$(body | jget reference_code)" "QK12345678" "receipt detail code"

UNKNOWN=$(printf '{"Body":{"stkCallback":{"CheckoutRequestID":"ws_CO_UNKNOWN","ResultCode":0,"ResultDesc":"ok","CallbackMetadata":{"Item":[{"Name":"MpesaReceiptNumber","Value":"QK99999999"}]}}}}')
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE$CALLBACK_PATH" -H 'Content-Type: application/json' -d "$UNKNOWN")
expect "$status" 200 "unknown checkout acknowledged"
status=$(call GET "/groups/$GROUP/transactions" "" "$ADMIN")
COUNT=$(body | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.data.length)})')
expect "$COUNT" "1" "unknown checkout wrote nothing"

status=$(call POST "/groups/$GROUP/payments/stk" '{"amount":"1500.00","purpose":"contribution"}' "$ADMIN" -H "X-Step-Up-Token: $STEP" -H "Idempotency-Key: stk-${SUFFIX}-e" -H "X-Client: web")
expect "$status" 202 "second STK for pagination"
status=$(call GET "/groups/$GROUP/transactions?limit=1" "" "$ADMIN")
expect "$(body | jget page.has_more)" "true" "cursor pagination reports more"
NEXT=$(body | jget page.next_cursor)
status=$(call GET "/groups/$GROUP/transactions?limit=1&cursor=$NEXT" "" "$ADMIN")
expect "$status" 200 "second page with cursor"

echo
if [ "$fails" -eq 0 ]; then echo "payments e2e: all checks passed"; else echo "payments e2e: $fails check(s) failed"; fi
exit "$fails"
