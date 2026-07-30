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
  "onboardingCompleted": false
}
```

### `POST /me/onboarding-complete`

Requires Bearer access token. Saves general availability and marks onboarding finished.

```json
{
  "weekdayAvailability": "After 6:00 PM",
  "weekendAvailability": "Anytime",
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
