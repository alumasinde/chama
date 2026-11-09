#!/usr/bin/env bash
# End-to-end check of Phase 2: chamas, invites, approval, roles, payment settings.
set -uo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
API="$BASE/api/v1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

jget() {
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);let v=j;for(const k of process.argv[1].split("."))v=v==null?undefined:v[k];console.log(v===undefined||v===null?"":String(v))}catch(e){console.log("")}})' "$1"
}

call() { # method path [data] [auth]
  local method="$1" path="$2" data="${3:-}" auth="${4:-}"
  local args=(-s -o "$TMP/body" -w '%{http_code}' -X "$method" "$API$path" -H 'Content-Type: application/json')
  [ -n "$auth" ] && args+=(-H "Authorization: Bearer $auth")
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
  local got="$1" label="$2"
  if [ -n "$got" ]; then echo "PASS  $label"; else echo "FAIL  $label (empty)"; fails=$((fails + 1)); fi
}
expect_diff() {
  local a="$1" b="$2" label="$3"
  if [ "$a" != "$b" ]; then echo "PASS  $label"; else echo "FAIL  $label (values equal)"; fails=$((fails + 1)); fi
}
body() { cat "$TMP/body"; }

register() { # $1 phone, $2 first, $3 last; sets ACCESS REFRESH USER_ID
  local phone="$1" first="$2" last="$3"
  call POST /auth/otp/request "{\"phone_number\":\"$phone\",\"purpose\":\"registration\"}" >/dev/null
  local code; code=$(body | jget dev_code)
  call POST /auth/otp/verify "{\"phone_number\":\"$phone\",\"code\":\"$code\",\"purpose\":\"registration\"}" >/dev/null
  local reg; reg=$(body | jget registration_token)
  call POST /auth/register "{\"first_name\":\"$first\",\"last_name\":\"$last\",\"pin\":\"4826\",\"password\":\"ChamaStrong2026\"}" "$reg" >/dev/null
  ACCESS=$(body | jget access_token)
  REFRESH=$(body | jget refresh_token)
  USER_ID=$(body | jget user.id)
  if [ -z "$ACCESS" ]; then
    echo "FAIL  could not register $phone: $(body)"
    exit 1
  fi
}

SUFFIX=$(printf '%06d' $((RANDOM % 1000000)))
register "07${SUFFIX}01" "Admin" "One"; ADMIN="$ACCESS"; ADMIN_ID="$USER_ID"
register "07${SUFFIX}02" "Member" "Two"; MEMBER="$ACCESS"; MEMBER_ID="$USER_ID"
register "07${SUFFIX}03" "Outsider" "Three"; OUTSIDER="$ACCESS"

echo "== create =="
status=$(call POST /groups '{"name":"Umoja Women","description":"Monthly savings","contribution_amount":"1500.50","contribution_frequency":"monthly","contribution_day":5,"late_grace_days":3}' "$ADMIN")
expect "$status" 201 "create chama"
GROUP=$(body | jget id)
INVITE=$(body | jget invite_code)
[ ${#INVITE} -eq 8 ] && echo "PASS  invite code is 8 characters" || { echo "FAIL  invite code shape"; fails=$((fails + 1)); }
expect "$(body | jget contribution_amount)" "1500.50" "amount stored exactly"
expect "$(body | jget role)" "admin" "creator is admin"

status=$(call GET /groups "" "$ADMIN"); expect "$status" 200 "admin lists chamas"
expect "$(body | jget data.0.active_members)" "1" "one active member"

status=$(call GET "/groups/$GROUP" "" "$ADMIN"); expect "$status" 200 "admin reads chama"
status=$(call GET "/groups/$GROUP" "" "$OUTSIDER"); expect "$status" 404 "non-member gets 404"
status=$(call GET "/groups/00000000-0000-0000-0000-000000000000" "" "$ADMIN"); expect "$status" 404 "unknown chama 404"

echo "== join and approval =="
status=$(call POST /groups/join "{\"invite_code\":\"$INVITE\"}" "$MEMBER"); expect "$status" 200 "join with invite"
expect "$(body | jget status)" "pending" "membership starts pending"
status=$(call POST /groups/join "{\"invite_code\":\"$INVITE\"}" "$MEMBER"); expect "$status" 200 "repeat join is idempotent"
status=$(call GET "/groups/$GROUP/members" "" "$MEMBER"); expect "$status" 403 "pending member cannot list members"
expect "$(body | jget error.code)" "membership_pending" "pending code"

status=$(call GET "/groups/$GROUP/members" "" "$ADMIN"); expect "$status" 200 "admin lists members"
expect "$(body | jget data.1.status)" "pending" "member visible as pending"

status=$(call PATCH "/groups/$GROUP/members/$MEMBER_ID" '{"status":"active"}' "$ADMIN"); expect "$status" 200 "admin approves member"
expect "$(body | jget status)" "active" "member now active"
status=$(call GET "/groups/$GROUP/members" "" "$MEMBER"); expect "$status" 200 "active member can list members"

echo "== roles =="
status=$(call PATCH "/groups/$GROUP" '{"name":"Renamed","contribution_amount":"100","contribution_frequency":"weekly"}' "$MEMBER"); expect "$status" 403 "plain member cannot edit chama"
status=$(call PATCH "/groups/$GROUP/members/$MEMBER_ID" '{"role":"treasurer"}' "$ADMIN"); expect "$status" 200 "admin promotes treasurer"
status=$(call GET "/groups/$GROUP/payment-settings" "" "$MEMBER"); expect "$status" 200 "treasurer reads payment settings"
status=$(call POST "/groups/$GROUP/invites/rotate" "" "$MEMBER"); expect "$status" 403 "treasurer cannot rotate invite"
status=$(call PATCH "/groups/$GROUP/members/$ADMIN_ID" '{"status":"exited"}' "$ADMIN"); expect "$status" 409 "last admin cannot leave"
expect "$(body | jget error.code)" "last_admin" "last admin code"

echo "== payment settings =="
status=$(call GET "/groups/$GROUP/payment-settings" "" "$ADMIN"); expect "$status" 200 "settings start unconfigured"
expect "$(body | jget configured)" "false" "configured false before save"
status=$(call PUT "/groups/$GROUP/payment-settings" '{"shortcode_type":"paybill","shortcode":"247247","daraja_environment":"sandbox"}' "$ADMIN")
expect "$status" 400 "first save without secrets rejected"
status=$(call PUT "/groups/$GROUP/payment-settings" '{"shortcode_type":"paybill","shortcode":"247247","daraja_environment":"sandbox","consumer_key":"ck_live_1234567890","consumer_secret":"cs_live_1234567890","passkey":"pk_live_1234567890"}' "$ADMIN")
expect "$status" 200 "save credentials"
CALLBACK=$(body | jget callback_url)
expect_not_empty "$CALLBACK" "callback URL returned once"
expect "$(body | jget consumer_key_masked)" "••••7890" "consumer key masked"
if body | grep -q "cs_live_1234567890"; then echo "FAIL  consumer secret leaked in response"; fails=$((fails + 1)); else echo "PASS  consumer secret not in response"; fi
status=$(call GET "/groups/$GROUP/payment-settings" "" "$ADMIN"); expect "$status" 200 "read saved settings"
if body | grep -q "ck_live_1234567890"; then echo "FAIL  consumer key stored in clear"; fails=$((fails + 1)); else echo "PASS  consumer key not returned in clear"; fi
status=$(curl -s -o "$TMP/body" -w '%{http_code}' -X PUT "$API/groups/$GROUP/payment-settings" -H 'Content-Type: application/json' -H "Authorization: Bearer $MEMBER" -d '{"shortcode_type":"till","shortcode":"123456","daraja_environment":"sandbox"}')
expect "$status" 200 "treasurer updates without resending secrets"
expect "$(body | jget consumer_key_masked)" "••••7890" "saved secrets are preserved"

echo "== invite rotation =="
status=$(call POST "/groups/$GROUP/invites/rotate" "" "$ADMIN"); expect "$status" 200 "admin rotates invite"
NEW_INVITE=$(body | jget invite_code)
expect_diff "$NEW_INVITE" "$INVITE" "invite code changed"
status=$(call POST /groups/join "{\"invite_code\":\"$INVITE\"}" "$OUTSIDER"); expect "$status" 404 "old code rejected"
status=$(call POST /groups/join "{\"invite_code\":\"$NEW_INVITE\"}" "$OUTSIDER"); expect "$status" 200 "new code accepted"
status=$(call POST /groups/join '{"invite_code":"ZZZZZZZZ"}' "$OUTSIDER"); expect "$status" 404 "unknown code rejected"

echo
if [ "$fails" -eq 0 ]; then echo "groups e2e: all checks passed"; else echo "groups e2e: $fails check(s) failed"; fi
exit "$fails"
