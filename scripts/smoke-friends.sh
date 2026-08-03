#!/usr/bin/env bash
# End-to-end check of the Phase 0 + Phase 1 surface: sign in two users, publish their
# public keys, pair them with an invite code, list friends, and revoke.
# Requires the server running with APPLE_VERIFY_TOKEN=false.
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"

b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='; }

fake_apple_token() {
  local sub="$1"
  local header payload
  header=$(b64url '{"alg":"none","typ":"JWT"}')
  payload=$(b64url "{\"sub\":\"$sub\",\"aud\":\"bhanageviraj.indeKismet\",\"email\":\"$sub@example.com\",\"exp\":4102444800}")
  printf '%s.%s.sig' "$header" "$payload"
}

sign_in() {
  local sub="$1" given="$2" family="$3"
  curl -sS -X POST "$BASE/auth/apple" \
    -H 'Content-Type: application/json' \
    -d "{\"identityToken\":\"$(fake_apple_token "$sub")\",\"fullName\":{\"givenName\":\"$given\",\"familyName\":\"$family\"},\"email\":\"$sub@example.com\"}"
}

jqr() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }
jqlen() { python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d[sys.argv[1]]))" "$1"; }

SUFFIX="$(date +%s)"
echo "== signing in two users =="
A_JSON=$(sign_in "smoke-a-$SUFFIX" Ada Lovelace)
B_JSON=$(sign_in "smoke-b-$SUFFIX" Grace Hopper)
A_TOKEN=$(printf '%s' "$A_JSON" | jqr "['accessToken']")
B_TOKEN=$(printf '%s' "$B_JSON" | jqr "['accessToken']")
A_ID=$(printf '%s' "$A_JSON" | jqr "['user']['id']")
B_ID=$(printf '%s' "$B_JSON" | jqr "['user']['id']")
echo "A=$A_ID  B=$B_ID"

auth_a() { curl -sS -H "Authorization: Bearer $A_TOKEN" "$@"; }
auth_b() { curl -sS -H "Authorization: Bearer $B_TOKEN" "$@"; }

echo
echo "== publishing public keys =="
auth_a -X PUT "$BASE/me/public-key" -H 'Content-Type: application/json' \
  -d '{"publicKey":"AAAA-ada-x25519-pubkey","keyVersion":1}' | jqr "['keyVersion']"
auth_b -X PUT "$BASE/me/public-key" -H 'Content-Type: application/json' \
  -d '{"publicKey":"BBBB-grace-x25519-pubkey","keyVersion":1}' | jqr "['keyVersion']"

echo
echo "== A rotates to v3 =="
auth_a -X PUT "$BASE/me/public-key" -H 'Content-Type: application/json' \
  -d '{"publicKey":"AAAA-ada-x25519-pubkey-v3","keyVersion":3}' | jqr "['keyVersion']"
echo -n "replaying the older v2 key (expect 409): "
auth_a -o /dev/null -w '%{http_code}\n' -X PUT "$BASE/me/public-key" \
  -H 'Content-Type: application/json' -d '{"publicKey":"stale","keyVersion":2}'
echo -n "rotating key without bumping version (expect 409): "
auth_a -o /dev/null -w '%{http_code}\n' -X PUT "$BASE/me/public-key" \
  -H 'Content-Type: application/json' -d '{"publicKey":"different","keyVersion":3}'
echo -n "version below 1 (expect 400): "
auth_a -o /dev/null -w '%{http_code}\n' -X PUT "$BASE/me/public-key" \
  -H 'Content-Type: application/json' -d '{"publicKey":"stale","keyVersion":0}'

echo
echo "== timezone =="
auth_a -X PUT "$BASE/me/timezone" -H 'Content-Type: application/json' \
  -d '{"timeZoneId":"Asia/Singapore"}' | jqr "['timeZoneId']"
echo -n "bad timezone (expect 400): "
auth_a -o /dev/null -w '%{http_code}\n' -X PUT "$BASE/me/timezone" \
  -H 'Content-Type: application/json' -d '{"timeZoneId":"Middle/Earth"}'

echo
echo "== A mints an invite code =="
INVITE=$(auth_a -X POST "$BASE/friends/invite")
CODE=$(printf '%s' "$INVITE" | jqr "['code']")
echo "$INVITE"

echo
echo "== A cannot redeem their own code (expect 400) =="
auth_a -o /dev/null -w '%{http_code}\n' -X POST "$BASE/friends/redeem" \
  -H 'Content-Type: application/json' -d "{\"inviteCode\":\"$CODE\"}"

echo
echo "== B redeems it (lowercased + dashed, to prove normalization) =="
LOWER=$(printf '%s' "$CODE" | tr 'A-Z' 'a-z')
auth_b -X POST "$BASE/friends/redeem" -H 'Content-Type: application/json' \
  -d "{\"inviteCode\":\"${LOWER:0:4}-${LOWER:4:4}\"}"

echo
echo "== single-use code cannot be redeemed twice (expect 404) =="
auth_b -o /dev/null -w '%{http_code}\n' -X POST "$BASE/friends/redeem" \
  -H 'Content-Type: application/json' -d "{\"inviteCode\":\"$CODE\"}"

echo
echo "== A's friend list (should show B and B's public key) =="
auth_a "$BASE/friends"
echo
echo "== B's friend list (should show A) =="
auth_b "$BASE/friends"

echo
echo "== unauthenticated access is rejected (expect 401/403) =="
curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/friends"

echo
echo "== A revokes B =="
auth_a -o /dev/null -w '%{http_code}\n' -X DELETE "$BASE/friends/$B_ID"
echo -n "A's friends after revoke: "
auth_a "$BASE/friends"
echo -n "B's friends after revoke: "
auth_b "$BASE/friends"

echo
echo "== re-pairing after revoke reuses the row =="
CODE2=$(auth_a -X POST "$BASE/friends/invite" | jqr "['code']")
auth_b -X POST "$BASE/friends/redeem" -H 'Content-Type: application/json' \
  -d "{\"inviteCode\":\"$CODE2\"}"
echo
echo "== already-connected redeem is rejected (expect 409) =="
CODE3=$(auth_a -X POST "$BASE/friends/invite" | jqr "['code']")
auth_b -o /dev/null -w '%{http_code}\n' -X POST "$BASE/friends/redeem" \
  -H 'Content-Type: application/json' -d "{\"inviteCode\":\"$CODE3\"}"

echo
echo "== onboarding sets availability and timezone =="
DAYS='[{"day":"monday","startMinutes":1080,"endMinutes":1440,"busySegments":[]},
{"day":"tuesday","startMinutes":1080,"endMinutes":1440,"busySegments":[]},
{"day":"wednesday","startMinutes":1080,"endMinutes":1440,"busySegments":[]},
{"day":"thursday","startMinutes":1080,"endMinutes":1440,"busySegments":[]},
{"day":"friday","startMinutes":1080,"endMinutes":1440,"busySegments":[]},
{"day":"saturday","startMinutes":360,"endMinutes":1440,"busySegments":[]},
{"day":"sunday","startMinutes":360,"endMinutes":1440,"busySegments":[]}]'
auth_b -o /dev/null -w 'B onboarding: %{http_code}\n' -X POST "$BASE/me/onboarding-complete" \
  -H 'Content-Type: application/json' \
  -d "{\"weekdayAvailability\":\"After 6:00 PM\",\"weekendAvailability\":\"Anytime\",\"timeZoneId\":\"Asia/Singapore\",\"dailyAvailability\":$DAYS}"

echo
echo "== A uploads an encrypted blob for B =="
auth_a -X POST "$BASE/blobs" -H 'Content-Type: application/json' \
  -d "{\"blobs\":[{\"recipientUserId\":\"$B_ID\",\"kind\":\"LOCATION\",\"ciphertext\":\"sealed-payload-v1\",\"keyVersion\":3}]}"

echo
echo "== A cannot address a blob to a stranger (expect 403) =="
auth_a -o /dev/null -w '%{http_code}\n' -X POST "$BASE/blobs" \
  -H 'Content-Type: application/json' \
  -d '{"blobs":[{"recipientUserId":"000000000000000000000000","kind":"LOCATION","ciphertext":"x","keyVersion":1}]}'

echo
echo "== B fetches pending blobs (ciphertext must be present) =="
auth_b "$BASE/blobs/pending"

echo
echo "== A re-uploads; the slot is replaced, not appended =="
auth_a -o /dev/null -X POST "$BASE/blobs" -H 'Content-Type: application/json' \
  -d "{\"blobs\":[{\"recipientUserId\":\"$B_ID\",\"kind\":\"LOCATION\",\"ciphertext\":\"sealed-payload-v2\",\"keyVersion\":3}]}"
echo -n "blob count for B (expect 1): "
auth_b "$BASE/blobs/pending" | jqlen blobs

echo
echo "== B's map view: availability, no coordinates, blob freshness =="
auth_b "$BASE/map/friends"

echo
echo "== A's map view of B (B configured availability, so status is real) =="
auth_a "$BASE/map/friends"

echo
echo "== revoking deletes the relayed ciphertext =="
auth_a -o /dev/null -w 'revoke: %{http_code}\n' -X DELETE "$BASE/friends/$B_ID"
echo -n "B's pending blobs after revoke (expect 0): "
auth_b "$BASE/blobs/pending" | jqlen blobs
echo -n "B's map friends after revoke (expect 0): "
auth_b "$BASE/map/friends" | jqlen friends

echo
echo "smoke test complete"
