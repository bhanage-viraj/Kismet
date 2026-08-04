#!/usr/bin/env bash
# Smoke-test POST /friends/pair (Bump path) and confirm invite/redeem still works.
# Requires the server running with APPLE_VERIFY_TOKEN=false.
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"

b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='; }

fake_apple_token() {
  local sub="$1"
  local header payload
  local aud="${APPLE_AUD:-bhanageviraj.indeKismet}"
  header=$(b64url '{"alg":"none","typ":"JWT"}')
  # aud must be listed in APPLE_CLIENT_ID (override with APPLE_AUD=…).
  payload=$(b64url "{\"sub\":\"$sub\",\"aud\":\"$aud\",\"email\":\"$sub@example.com\",\"exp\":4102444800}")
  printf '%s.%s.sig' "$header" "$payload"
}

sign_in() {
  local sub="$1" given="$2" family="$3"
  curl -sS -X POST "$BASE/auth/apple" \
    -H 'Content-Type: application/json' \
    -d "{\"identityToken\":\"$(fake_apple_token "$sub")\",\"fullName\":{\"givenName\":\"$given\",\"familyName\":\"$family\"},\"email\":\"$sub@example.com\"}"
}

jqr() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }

SUFFIX="$(date +%s)"
echo "== signing in two users =="
A_JSON=$(sign_in "bump-a-$SUFFIX" Ada Lovelace)
B_JSON=$(sign_in "bump-b-$SUFFIX" Grace Hopper)
A_TOKEN=$(printf '%s' "$A_JSON" | jqr "['accessToken']")
B_TOKEN=$(printf '%s' "$B_JSON" | jqr "['accessToken']")
A_ID=$(printf '%s' "$A_JSON" | jqr "['user']['id']")
B_ID=$(printf '%s' "$B_JSON" | jqr "['user']['id']")
echo "A=$A_ID  B=$B_ID"

auth_a() { curl -sS -H "Authorization: Bearer $A_TOKEN" "$@"; }
auth_b() { curl -sS -H "Authorization: Bearer $B_TOKEN" "$@"; }

echo "== publish public keys =="
auth_a -X PUT "$BASE/me/public-key" -H 'Content-Type: application/json' \
  -d '{"publicKey":"bump-a-key","keyVersion":1}' >/dev/null
auth_b -X PUT "$BASE/me/public-key" -H 'Content-Type: application/json' \
  -d '{"publicKey":"bump-b-key","keyVersion":1}' >/dev/null

echo "== POST /friends/pair (Bump) =="
PAIR=$(auth_a -X POST "$BASE/friends/pair" -H 'Content-Type: application/json' \
  -d "{\"peerUserId\":\"$B_ID\",\"peerPublicKey\":\"bump-b-key\"}")
VIA=$(printf '%s' "$PAIR" | jqr "['connectedVia']")
STATUS=$(printf '%s' "$PAIR" | jqr "['status']")
test "$VIA" = "BUMP"
test "$STATUS" = "ACTIVE"
echo "paired via $VIA"

echo "== duplicate pair is 409 =="
CODE=$(auth_a -o /dev/null -w '%{http_code}' -X POST "$BASE/friends/pair" \
  -H 'Content-Type: application/json' \
  -d "{\"peerUserId\":\"$B_ID\"}")
test "$CODE" = "409"
echo "conflict=$CODE"

echo "== both sides see each other =="
A_FRIENDS=$(auth_a "$BASE/friends")
B_FRIENDS=$(auth_b "$BASE/friends")
printf '%s' "$A_FRIENDS" | python3 -c "import sys,json;d=json.load(sys.stdin);assert any(f['userId']=='$B_ID' and f.get('connectedVia')=='BUMP' for f in d['friends'])"
printf '%s' "$B_FRIENDS" | python3 -c "import sys,json;d=json.load(sys.stdin);assert any(f['userId']=='$A_ID' for f in d['friends'])"
echo "lists ok"

echo "== self-pair rejected =="
SELF=$(auth_a -o /dev/null -w '%{http_code}' -X POST "$BASE/friends/pair" \
  -H 'Content-Type: application/json' \
  -d "{\"peerUserId\":\"$A_ID\"}")
test "$SELF" = "400"
echo "self=$SELF"

echo "== invite/redeem regression on a third pair of users =="
C_JSON=$(sign_in "bump-c-$SUFFIX" Carol Test)
D_JSON=$(sign_in "bump-d-$SUFFIX" Dave Test)
C_TOKEN=$(printf '%s' "$C_JSON" | jqr "['accessToken']")
D_TOKEN=$(printf '%s' "$D_JSON" | jqr "['accessToken']")
auth_c() { curl -sS -H "Authorization: Bearer $C_TOKEN" "$@"; }
auth_d() { curl -sS -H "Authorization: Bearer $D_TOKEN" "$@"; }
INVITE=$(auth_c -X POST "$BASE/friends/invite")
CODE_INV=$(printf '%s' "$INVITE" | jqr "['code']")
REDEEM=$(auth_d -X POST "$BASE/friends/redeem" -H 'Content-Type: application/json' \
  -d "{\"inviteCode\":\"$CODE_INV\"}")
test "$(printf '%s' "$REDEEM" | jqr "['connectedVia']")" = "INVITE_CODE"
echo "invite/redeem still INVITE_CODE"

echo "OK — Bump pair + invite/redeem regression passed"
