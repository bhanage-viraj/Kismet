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

## Errors

```json
{
  "status": 401,
  "message": "Invalid Apple identity token",
  "timestamp": "2026-07-30T00:00:00Z"
}
```

## Local config

See `server/.env.example`:

| Variable | Notes |
|----------|--------|
| `APPLE_CLIENT_ID` | Must match iOS bundle ID (`bhanageviraj.Kismet`) for native Sign in with Apple |
| `APPLE_VERIFY_TOKEN` | `false` only for local Simulator demos; production must be `true` |
| `JWT_SECRET` | At least 32 characters |
| `MONGODB_URI` | Default `mongodb://localhost:27017/kismet` |
| `INVITE_CODE_TTL_MINUTES` | Invite code lifetime, default `60` |
| `MAX_FRIENDS` | Active friendships per user, default `500` |

`scripts/smoke-friends.sh` exercises this whole surface end to end against a running server.
