#!/usr/bin/env bash
# End-to-end check of the Phase 1 auth stack against a running server.
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
  local method="$1" path="$2" data="${3:-}" auth="${4:-}"
  local args=(-s -o "$TMP/body" -w '%{http_code}' -X "$method" "$API$path" -H 'Content-Type: application/json')
  [ -n "$auth" ] && args+=(-H "Authorization: Bearer $auth")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}

expect() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label (got '$got', want '$want')"
    cat "$TMP/body"; echo
    fails=$((fails + 1))
  fi
}

body() { cat "$TMP/body"; }

PHONE="+2547$(printf '%08d' $(((RANDOM * 32768 + RANDOM) % 100000000)))"
LOCAL="0${PHONE#+254}"
PIN=4826
PASSWORD="ChamaStrong2026"

echo "== phone $PHONE =="

status=$(call GET /meta); expect "$status" 200 "meta responds"
expect "$(body | jget app_name)" "Chama Ledger" "app name comes from branding.json"

status=$(call POST /auth/otp/request "{\"phone_number\":\"$LOCAL\",\"purpose\":\"registration\"}")
expect "$status" 200 "otp request (accepts local format)"
CODE=$(body | jget dev_code)
[ ${#CODE} -eq 6 ] && echo "PASS  dev code returned" || { echo "FAIL  dev code missing"; fails=$((fails + 1)); }

status=$(call POST /auth/otp/verify "{\"phone_number\":\"$LOCAL\",\"code\":\"$CODE\",\"purpose\":\"registration\"}")
expect "$status" 200 "otp verify"
REG=$(body | jget registration_token)

status=$(call POST /auth/register "{\"first_name\":\"Wanjiku\",\"last_name\":\"Kamau\",\"pin\":\"$PIN\",\"password\":\"$PASSWORD\"}" "$REG")
expect "$status" 201 "register with 4-digit PIN and password"
ACCESS=$(body | jget access_token)
REFRESH=$(body | jget refresh_token)
expect "$(body | jget user.display_name)" "Wanjiku Kamau" "display name built from first and last"
expect "$(body | jget user.pin_set)" "true" "pin_set is true"

status=$(call GET /me "" "$ACCESS"); expect "$status" 200 "profile with access token"
expect "$(body | jget user.phone_number)" "$PHONE" "phone normalised to E.164"

status=$(call POST /auth/pin/verify '{"pin":"9999"}' "$ACCESS"); expect "$status" 422 "wrong PIN rejected"
expect "$(body | jget error.code)" "pin_incorrect" "wrong PIN code"

status=$(call POST /auth/pin/verify "{\"pin\":\"$PIN\"}" "$ACCESS"); expect "$status" 200 "correct PIN mints step-up"
STEP=$(body | jget step_up_token)
[ ${#STEP} -gt 20 ] && echo "PASS  step-up token present" || { echo "FAIL  step-up token missing"; fails=$((fails + 1)); }

status=$(call POST /auth/token/refresh "{\"refresh_token\":\"$REFRESH\"}"); expect "$status" 200 "refresh rotates"
NEW_REFRESH=$(body | jget refresh_token)
[ "$NEW_REFRESH" != "$REFRESH" ] && echo "PASS  refresh token changed" || { echo "FAIL  refresh token not rotated"; fails=$((fails + 1)); }

status=$(call POST /auth/token/refresh "{\"refresh_token\":\"$REFRESH\"}"); expect "$status" 401 "reusing rotated token rejected"
status=$(call POST /auth/token/refresh "{\"refresh_token\":\"$NEW_REFRESH\"}"); expect "$status" 401 "family revoked after reuse"

status=$(call POST /auth/login "{\"phone_number\":\"$LOCAL\",\"password\":\"$PASSWORD\"}"); expect "$status" 200 "password login"
ACCESS2=$(body | jget access_token)

for i in 1 2 3 4; do
  status=$(call POST /auth/pin/verify '{"pin":"1357"}' "$ACCESS2")
  expect "$status" 422 "wrong PIN $i"
done
status=$(call POST /auth/pin/verify '{"pin":"1357"}' "$ACCESS2"); expect "$status" 422 "fifth wrong PIN"
expect "$(body | jget error.code)" "pin_locked" "PIN locks after five failures"
status=$(call POST /auth/pin/verify "{\"pin\":\"$PIN\"}" "$ACCESS2"); expect "$status" 422 "locked PIN rejects correct value"

status=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/healthz"); expect "$status" 200 "healthz"
status=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/readyz"); expect "$status" 200 "readyz"

status=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/"); expect "$status" 200 "SPA fallback serves index"
grep -q 'id="app"' "$TMP/body" && echo "PASS  index.html content" || { echo "FAIL  index.html content"; fails=$((fails + 1)); }

status=$(call GET /does-not-exist); expect "$status" 404 "unknown API path is JSON 404"
expect "$(body | jget error.code)" "not_found" "error envelope shape"

status=$(call POST /auth/login '{"phone_number":"0700000000","password":"nope-nope"}'); expect "$status" 401 "unknown phone login rejected"

echo
if [ "$fails" -eq 0 ]; then echo "e2e: all checks passed"; else echo "e2e: $fails check(s) failed"; fi
exit "$fails"
