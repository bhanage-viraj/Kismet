# Kismet API

Base URL (local): `http://localhost:8080`

Auth uses Bearer JWT access tokens. Refresh tokens are opaque JWTs stored hashed server-side.

## Auth

### `POST /auth/apple`

Public. Exchange an Apple identity token for Kismet session tokens.

```json
{
  "identityToken": "<Apple JWT>",
  "fullName": {
    "givenName": "Ada",
    "familyName": "Lovelace"
  },
  "email": "optional@privaterelay.appleid.com",
  "interests": ["coffee", "coding", "travel"]
}
```

`fullName` and `email` are only sent by Apple on the first authorization; omit them on later sign-ins.

**Response `200`:**

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 3600,
  "user": {
    "id": "...",
    "displayName": "Ada Lovelace",
    "email": "optional@privaterelay.appleid.com",
    "interests": ["coffee", "coding", "travel"],
    "isNewUser": true,
    "onboardingCompleted": false
  }
}
```

### `POST /auth/refresh`

Public. Rotate tokens using a valid refresh token.

```json
{
  "refreshToken": "..."
}
```

Response shape matches `/auth/apple`.

### `POST /auth/logout`

Requires `Authorization: Bearer <accessToken>`. Clears the stored refresh token hash. Response `204`.

## User

### `GET /me`

Requires Bearer access token.

```json
{
  "id": "...",
  "displayName": "...",
  "email": "...",
  "interests": ["coffee", "coding", "travel"],
  "weekdayAvailability": "After 6:00 PM",
  "weekendAvailability": "Anytime",
  "dailyAvailability": {
    "monday": { "startMinutes": 1080, "endMinutes": 1440 },
    "sunday": { "startMinutes": 360, "endMinutes": 1440 }
  },
  "timeZoneId": "Asia/Singapore",
  "publicKey": "<base64 X25519>",
  "keyVersion": 1,
  "onboardingCompleted": false
}
```

### `POST /me/onboarding-complete`

Requires Bearer access token. Saves general availability and marks onboarding finished.

`timeZoneId` is an IANA zone and is optional but strongly recommended: without it the server cannot evaluate whether a user is free right now, because `dailyAvailability` is minutes-from-midnight with no anchor.

```json
{
  "weekdayAvailability": "After 6:00 PM",
  "weekendAvailability": "Anytime",
  "timeZoneId": "Asia/Singapore",
  "dailyAvailability": [
    {
      "day": "monday",
      "startMinutes": 1080,
      "endMinutes": 1440,
      "busySegments": [
        { "startMinutes": 1140, "endMinutes": 1200 }
      ]
    },
    { "day": "tuesday", "startMinutes": 1080, "endMinutes": 1440, "busySegments": [] },
    { "day": "wednesday", "startMinutes": 1080, "endMinutes": 1440, "busySegments": [] },
    { "day": "thursday", "startMinutes": 1080, "endMinutes": 1440, "busySegments": [] },
    { "day": "friday", "startMinutes": 1080, "endMinutes": 1440, "busySegments": [] },
    { "day": "saturday", "startMinutes": 360, "endMinutes": 1440, "busySegments": [] },
    { "day": "sunday", "startMinutes": 360, "endMinutes": 1440, "busySegments": [] }
  ]
}
```

Returns the same shape as `GET /me`.

### `POST /me/interests`

Requires Bearer access token. Saves the interests selected during onboarding.

```json
{
  "interests": ["coffee", "coding", "travel"]
}
```

### `PUT /me/timezone`

Requires Bearer access token. Body `{ "timeZoneId": "Asia/Singapore" }`. Rejects unknown zones with `400`. Returns the `GET /me` shape.

### `PUT /me/public-key`

Requires Bearer access token. Publishes the caller's X25519 public key so friends can seal encrypted blobs for them. The server treats the key as an opaque string and performs no cryptography with it.

```json
{
  "publicKey": "<base64 X25519 public key>",
  "keyVersion": 1
}
```

`keyVersion` must be at least `1` and must never decrease, so a replayed older key cannot downgrade a user back to a compromised keypair. Re-sending the identical key at the same version is idempotent. Returns the `GET /me` shape.

| Case | Status |
|------|--------|
| Version below `1` | `400` |
| Version lower than the stored one | `409` |
| Different key at the same version | `409` |

## Friends

Pairing is instant: redeeming a code creates an `ACTIVE` friendship with no approval step, since holding the code is the consent signal.

### `POST /friends/invite`

Requires Bearer access token. Mints a fresh single-use code and invalidates any previous code the caller had outstanding.

```json
{
  "code": "K0SFW008",
  "qrPayload": "kismet://pair?code=K0SFW008",
  "expiresAt": "2026-07-31T08:02:32.394149Z"
}
```

Codes are 8 characters of Crockford base32 (no `I`, `L`, `O` or `U`) and expire after `INVITE_CODE_TTL_MINUTES`, default 60.

### `POST /friends/redeem`

Requires Bearer access token. Body `{ "inviteCode": "K0SFW008" }`. Codes are matched case-insensitively and dashes and whitespace are stripped, so `k0sf-w008` works.

```json
{
  "pairId": "...",
  "userId": "...",
  "displayName": "Ada Lovelace",
  "publicKey": "<base64 X25519>",
  "keyVersion": 1,
  "status": "ACTIVE",
  "connectedVia": "INVITE_CODE",
  "since": "2026-07-31T07:02:32.463412Z",
  "initiatedByMe": true
}
```

| Case | Status |
|------|--------|
| Unknown or already-consumed code | `404` |
| Expired or exhausted code | `410` |
| Redeeming your own code | `400` |
| Already connected | `409` |
| Either side at the friend limit | `409` |

Re-pairing after a revoke reuses the existing row rather than creating a second one.

### `GET /friends`

Requires Bearer access token. Active friendships only, each with the friend's public key so the client can encrypt for them. `publicKey` is `null` until that friend publishes one.

```json
{
  "friends": [
    {
      "pairId": "...",
      "userId": "...",
      "displayName": "Grace Hopper",
      "publicKey": "<base64 X25519>",
      "keyVersion": 1,
      "status": "ACTIVE",
      "connectedVia": "INVITE_CODE",
      "since": "2026-07-31T07:02:32.463Z",
      "initiatedByMe": false
    }
  ]
}
```

### `DELETE /friends/{friendUserId}`

Requires Bearer access token. Revokes the friendship in both directions — there is no one-way unfriend. Response `204`. Already-revoked is also `204`; an unknown friendship is `404`.

## Blobs

The server relays opaque ciphertext and never decrypts it or holds key material. For `LOCATION` this collection behaves as a mailbox with one slot per (sender, recipient, kind): re-uploading replaces the previous blob rather than appending.

Blob kinds are `LOCATION`, `AVAILABILITY` and `MESSAGE`, matched case-insensitively.

### `POST /blobs`

Requires Bearer access token. Batched, because one location refresh produces a separate ciphertext per friend.

```json
{
  "blobs": [
    {
      "recipientUserId": "...",
      "kind": "LOCATION",
      "ciphertext": "<sealed payload>",
      "keyVersion": 3
    }
  ]
}
```

`keyVersion` is the *recipient's* key version the payload was sealed to, taken from `GET /friends`.

**Response `200`:** `{ "accepted": 1, "expiresAt": "2026-07-31T22:09:30Z" }`

| Case | Status |
|------|--------|
| Recipient is not an active friend | `403` |
| Recipient is yourself | `400` |
| Same recipient and kind twice in one request | `400` |
| Unknown kind, blank ciphertext or recipient | `400` |
| Ciphertext over `BLOB_MAX_CIPHERTEXT_BYTES`, or batch over `BLOB_MAX_BATCH_SIZE` | `413` |

### `GET /blobs/pending`

Requires Bearer access token. Everything addressed to the caller.

```json
{
  "blobs": [
    {
      "id": "...",
      "senderUserId": "...",
      "kind": "LOCATION",
      "ciphertext": "<sealed payload>",
      "keyVersion": 3,
      "updatedAt": "2026-07-31T10:09:30.072Z"
    }
  ]
}
```

### `POST /blobs/ack`

Requires Bearer access token. Body `{ "blobIds": ["..."] }`, returns `{ "deleted": 1 }`. Optional, since the TTL collects blobs anyway. Deletion is scoped to the caller, so acknowledging cannot destroy blobs addressed to anyone else.

Blobs expire after `BLOB_TTL_HOURS` and are deleted immediately in both directions when a friendship is revoked.

## Map

### `GET /map/friends`

Requires Bearer access token.

**There is no nearby endpoint, by design.** Proximity cannot be computed server-side against ciphertext, so this returns the plaintext half — who is free — and the client intersects it with the location blobs it decrypts locally.

```json
{
  "friends": [
    {
      "userId": "...",
      "displayName": "Grace Hopper",
      "availability": {
        "status": "FREE",
        "freeUntil": "2026-07-31T16:00:00Z",
        "freeFrom": null
      },
      "sharedInterests": ["coffee", "gym"],
      "hasLocationBlob": true,
      "blobUpdatedAt": "2026-07-31T10:09:53.459Z"
    }
  ]
}
```

`status` is `FREE`, `BUSY`, or `UNKNOWN` when the friend has no timezone or no availability configured. `freeUntil` is set only when free, `freeFrom` only when busy with free time scheduled within the week ahead.

`blobUpdatedAt` reports when that friend's location blob was last refreshed without revealing anything about its contents, so a client can render "last seen 3 minutes ago" and skip decrypting a blob it already handled.

### `GET /map/friends/{friendUserId}`

Requires Bearer access token. Same shape as one element above. Returns `404` if you are not connected.

## Realtime

STOMP over WebSocket at `ws://<host>/ws`.

The handshake is a plain HTTP upgrade that carries no bearer header, so `/ws/**` is permitted in the HTTP filter chain and authentication happens on the STOMP `CONNECT` frame instead. Send the access token as a native header:

```
CONNECT
Authorization: Bearer <accessToken>
```

A `CONNECT` without a valid access token is rejected. Subscribe to `/user/queue/map`:

```json
{ "type": "blob.available", "userId": "<sender id>", "at": "2026-07-31T10:09:53Z" }
```

Event types are `blob.available`, `friend.pair.created` and `friend.pair.revoked`. Blob events are **notifications only** and never carry ciphertext — fetch it with `GET /blobs/pending`.

The broker is in-memory, so this is single-instance only; scaling out means swapping in a Redis or RabbitMQ relay.

## Errors

Every error, including the ones raised by the security filter chain, uses one shape:

```json
{
  "status": 401,
  "message": "Invalid Apple identity token",
  "timestamp": "2026-07-30T00:00:00Z"
}
```

`401` and `403` are not interchangeable here. A missing, malformed or expired access token is always `401`, which is the client's signal to spend its refresh token and retry. `403` means the caller is authenticated but not allowed to touch that resource, such as addressing a blob to someone who is not an active friend; retrying after a refresh will not help.

## Local config

See `server/.env.example`:

| Variable | Notes |
|----------|--------|
| `ALLOW_INSECURE_CONFIG` | Permits the development auth settings below. Without it the server refuses to start on them |
| `APPLE_CLIENT_ID` | Must match iOS bundle ID (`bhanageviraj.Kismet`) for native Sign in with Apple |
| `APPLE_VERIFY_TOKEN` | `false` only for local Simulator demos; production must be `true` |
| `JWT_SECRET` | At least 32 characters |
| `MONGODB_URI` | Default `mongodb://localhost:27017/kismet` |
| `INVITE_CODE_TTL_MINUTES` | Invite code lifetime, default `60` |
| `MAX_FRIENDS` | Active friendships per user, default `500` |
| `BLOB_TTL_HOURS` | How long relayed ciphertext survives, default `12` |
| `BLOB_MAX_CIPHERTEXT_BYTES` | Per-blob size cap, default `4096` |
| `BLOB_MAX_BATCH_SIZE` | Blobs per upload, default `500` |

## Tests

`./mvnw test` runs the whole suite. It needs Docker: the integration tests start a real MongoDB via Testcontainers, because the unique slot index, upsert-on-refresh and TTL are database behaviour that a mocked repository would not exercise.

| Scope | Covers |
|-------|--------|
| `ApiFlowIntegrationTest` | The HTTP surface end to end: sign in, pair, relay, revoke, and the auth status codes |
| `MongoIndexIntegrationTest` | Index-level guarantees: duplicate pairs, one blob per slot, recipient-scoped deletes |
| Service tests | Branching and edge cases per service, with collaborators mocked |

`scripts/smoke-friends.sh` exercises the same surface against an already-running server, which is useful when checking a deployed instance rather than a build. Start that server with `ALLOW_INSECURE_CONFIG=true`, since the script signs in with unverified identity tokens.

## Startup safety check

`APPLE_VERIFY_TOKEN=false` and the development `JWT_SECRET` both fail open: the first accepts any unsigned identity token carrying a `sub` claim, and the second lets anyone holding the source mint access tokens for any account. Either one turns a forgotten environment variable into a full authentication bypass on an otherwise healthy-looking server.

`InsecureConfigurationGuard` therefore aborts startup when it finds them, reporting every problem at once, unless `ALLOW_INSECURE_CONFIG=true` opts in for local work.
