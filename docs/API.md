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
  "email": "optional@privaterelay.appleid.com"
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
  "onboardingCompleted": false
}
```

### `POST /me/onboarding-complete`

Requires Bearer access token. Marks onboarding finished. Returns the same shape as `GET /me`.

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
