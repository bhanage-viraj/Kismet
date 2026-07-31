# Kismet Map Backend — Architecture Plan (E2EE)

Backend only. iOS appears here only as the contract it has to speak.

## 0. Where we're starting from

The server today is an auth + profile service.

**Real and working:** `auth/*` (Sign in with Apple, JWT issue/rotate, refresh-hash storage), `user/*` (`UserDocument`, `/me`, `/me/onboarding-complete`, `/me/interests`, availability validation + busy-segment merging), `config/*` (`SecurityConfig`, `JwtAuthFilter`, `AuthUser`), `common/*` (error envelope).

**Empty stubs — zero methods, zero endpoints:** `blob/BlobService`, `blob/BlobController`, `blob/EncryptedBlobRepository`, `friend/FriendService`, `friend/FriendController`, `friend/FriendPairRepository`, `realtime/RealtimeEventPublisher`, `realtime/BlobAckController`, `push/PushTokenController`, `config/WebSocketConfig`.

`EncryptedBlobDocument`, `FriendPairDocument`, `BlobKind`, `PairStatus`, `ConnectedVia` and their DTO records exist as data shapes but nothing reads or writes them. `WebSocketConfig` doesn't implement `WebSocketMessageBrokerConfigurer`, so despite `spring-boot-starter-websocket` being on the classpath there is no WebSocket URL at all.

**Nothing geo exists.** No coordinate field, no `2dsphere` index, no geospatial dependency. The only hit for "location" in the whole backend is the unused `BlobKind.LOCATION` constant.

## 1. Architecture: the server is blind to location

**Decision: end-to-end encrypted blob relay.** The server never sees a coordinate. Clients encrypt their location for each friend individually, upload opaque ciphertext, and the server's only job is authenticated storage and delivery. Proximity is computed on the receiving device after decryption.

This has one large structural consequence that drives every design choice below: **there is no `GET /map/nearby` endpoint.** You cannot run a geospatial query against ciphertext. There is no `2dsphere` index, no `$geoNear`, and no server-side distance math anywhere in this plan. "Who's free nearby" is assembled on-device.

### The split that makes this practical

Availability is *already* stored in plaintext on `UserDocument`, and it's far less sensitive than a live coordinate. Rather than encrypting everything and making the server useless, split the question:

- **The server answers "who is free right now."** It has `dailyAvailability`, busy segments, and (after Phase 0) timezone. This is a cheap, indexed, server-side query.
- **The device answers "who is nearby."** It decrypts the location blobs its friends addressed to it and does the distance math locally.

The intersection of those two, computed on-device, is "who's free nearby." The server learns your schedule but never your position, and the expensive part (encryption fan-out) only applies to the genuinely sensitive field.

### Crypto model

X25519 key agreement plus an AEAD (ChaCha20-Poly1305 or AES-GCM), all via CryptoKit on-device in the existing `Core/Crypto/CryptoBox.swift` stub. The server stores and compares public keys as opaque base64 strings and performs **no** cryptographic operations on them.

Each user publishes one X25519 public key with a monotonically increasing `keyVersion`. `GET /friends` returns each friend's current public key and version, so the sender can derive a shared secret per recipient and seal the payload. When a user reinstalls or switches devices they publish a new key at a higher version; senders notice the version bump on their next friend-list refresh and re-encrypt. Blobs sealed to a superseded key are simply undecryptable and age out via TTL — acceptable, because location is ephemeral by nature and the next update arrives within minutes.

One key per user, stored on `UserDocument`, is the right scope for v1. Multi-device (a separate `device_keys` collection, fan-out per device) is a later change that doesn't disturb the API shape.

### What the server still learns

Be honest about the residual leakage, because "E2EE" is often oversold. The server sees the full social graph, and it sees blob sender, recipient, size, and timing. From update *frequency* alone it can infer coarse behavioral patterns — someone whose device stops posting for eight hours is probably asleep. What it cannot recover is *where anyone is*. Padding ciphertext to a fixed length is a cheap mitigation for size-based inference and is worth doing on the client.

## 2. Gaps in the existing model that block the map

**No timezone.** `dailyAvailability` stores minutes-from-midnight with nothing anchoring it. The server cannot currently decide whether a user is free right now — it doesn't know what "now" means for them. Add `timeZoneId` (IANA, e.g. `Asia/Singapore`) captured during availability onboarding.

**No public key.** Nothing to encrypt to. This is the foundation of the whole design.

**No friend-discoverable identity.** No invite code, no handle — nothing for a second user to reference when pairing.

All three are Phase 0 and Phase 1 work.

## 3. Data model

### `UserDocument` (extend)

Add `timeZoneId`, `publicKey` (base64 X25519, opaque to the server), `keyVersion` (int, monotonic), `keyUpdatedAt`.

### `friend_pairs` (extend the existing document)

Add `requestedByUserId`, `createdAt`, `acceptedAt`, `updatedAt`. Store `userAId` / `userBId` in **canonical order** — lexicographically smaller ID always in `userAId` — so a unique compound index actually prevents duplicate pairs regardless of who initiated.

Indexes: unique compound `(userAId, userBId)`; single-field on each for "list my friends".

### `invite_codes` (new)

`code` (unique, 8-char Crockford base32 — no ambiguous characters, since these get read aloud and retyped), `ownerUserId`, `expiresAt` (TTL indexed), `usesRemaining`, `createdAt`.

Short-lived rotating codes beat a permanent code on the user document: a leaked permanent code is a permanent liability, and QR display wants a fresh code anyway.

### `encrypted_blobs` (the existing document, extended)

Add `keyVersion` (which recipient key this was sealed to), `createdAt`, `expiresAt` (TTL indexed), and `nonce` if the client doesn't inline it in the ciphertext envelope.

**Critical design point: for `LOCATION`, this is a mailbox with exactly one slot per (sender, recipient), not an append log.** A unique compound index on `(senderUserId, recipientUserId, kind)` plus upsert-on-write means a user's location blob for a given friend is overwritten in place. Without this, a client posting every minute to 100 friends writes 144,000 documents a day. With it, storage is bounded at (friends × friends) and "pending blobs" is always a small, bounded fetch. `MESSAGE` blobs, if they ever ship, would append instead and need a different collection or a discriminated write path.

TTL on `expiresAt` (default 12 hours) is the privacy workhorse: a location that stops being refreshed disappears on its own rather than leaving a friend looking at a stale, misleading pin.

### `location_sharing_settings` (new) — `userId` as `@Id`

`defaultMode` (`PRECISE` / `APPROXIMATE` / `HIDDEN`), `pausedUntil` (ghost mode with auto-expiry), `perFriendOverrides`.

Note the difference from a plaintext design: **the server cannot enforce precision, because it cannot see coordinates.** Blurring happens on the sending client before encryption. This collection is a synced preferences store so settings survive reinstall and stay consistent across devices — it is not an enforcement point. Revocation, by contrast, *is* server-enforced: a revoked pair means uploads addressed to that user are rejected and their existing blobs are deleted.

## 4. API surface

All authenticated via the existing `JwtAuthFilter` / `AuthUser` principal, all errors through the existing `ApiExceptionHandler` envelope.

### Keys

| Endpoint | Purpose |
|---|---|
| `PUT /me/public-key` | `{ publicKey, keyVersion }`. Rejects a version lower than the stored one, so a replayed old key can't downgrade you |

### Friends (prerequisite — a map with no friends renders nothing)

| Endpoint | Purpose |
|---|---|
| `POST /friends/invite` | Mint a short-lived code. Returns `{ code, qrPayload, expiresAt }` |
| `POST /friends/redeem` | `{ code }` → resolves owner, creates an `ACTIVE` pair. Rejects self-pairing and duplicates |
| `GET /friends` | `{ userId, displayName, publicKey, keyVersion, status, connectedVia, since }` — the public key is here because the client needs it to encrypt |
| `DELETE /friends/{friendUserId}` | Sets `REVOKED`, and deletes all blobs between the two users in both directions |

Pairing is instant-`ACTIVE` on redeem: possessing the code is the consent signal, the same model as AirDrop.

### Blobs

| Endpoint | Purpose |
|---|---|
| `POST /blobs` | Batch upload: `{ blobs: [{ recipientUserId, kind, ciphertext, keyVersion }] }`. Every recipient is verified to be an `ACTIVE` friend; upserts on `(sender, recipient, kind)` |
| `GET /blobs/pending` | Everything addressed to me. Returns `{ id, senderUserId, kind, ciphertext, keyVersion, createdAt }` |
| `POST /blobs/ack` | `{ blobIds }` → delete. Optional, since TTL collects them anyway |

Batch upload matters: a location refresh means one blob per friend, and doing that as N round trips from a phone on cellular is not viable.

**The existing `CreateBlobResponse(id, kind)` record carries no ciphertext**, so `PendingBlobsResponse` as currently shaped physically cannot deliver blob contents to a client. That DTO needs a separate read shape — a real bug baked into the scaffold.

Size-cap `ciphertext` (a few KB) and cap batch length at the friend limit. The server can't inspect these payloads, so the only defenses available are structural: size, count, rate.

### Availability (the plaintext half)

| Endpoint | Purpose |
|---|---|
| `GET /map/friends` | Every accepted friend with availability status, `lastSeen`, shared interests, and `hasLocationBlob`. **No coordinates.** The client joins this against decrypted blobs |
| `GET /map/friends/{id}` | Detail: today's window, next mutual free slot, shared interests |

Element shape:

```json
{
  "userId": "...",
  "displayName": "Ada",
  "availability": { "status": "FREE", "freeUntil": "2026-07-31T14:00:00Z" },
  "sharedInterests": ["coffee", "gym"],
  "hasLocationBlob": true,
  "blobUpdatedAt": "2026-07-31T06:40:00Z"
}
```

`blobUpdatedAt` lets the client show "last seen 3 minutes ago" without decrypting anything, and lets it skip a decrypt it has already done.

### Free-now computation

An `AvailabilityEvaluator` service — pure, no I/O, trivially unit-testable:

> Given `dailyAvailability`, `timeZoneId`, and an `Instant`, resolve to the user's local day and minutes-from-midnight. Inside `[startMinutes, endMinutes)` and outside every busy segment → `FREE`, with `freeUntil` = the next busy-segment start or the window end, whichever is sooner. Otherwise `BUSY` with `freeFrom` = the next free boundary.

This reuses the busy-segment merging `UserService` already does, so segments arrive sorted and non-overlapping and the scan is linear.

## 5. Realtime

`WebSocketConfig` implements `WebSocketMessageBrokerConfigurer`: STOMP at `/ws`, in-memory broker on `/topic` and `/queue`, app prefix `/app`, user prefix `/user`.

Authentication: a `ChannelInterceptor` on the inbound channel reads the JWT from the STOMP `CONNECT` frame's `Authorization` header, validates it with the existing `JwtService`, and sets `AuthUser` as the session principal. **`SecurityConfig` must permit `/ws/**` at the HTTP layer** — the handshake is a plain HTTP upgrade carrying no bearer header, so auth has to happen at the STOMP frame level instead. Missing this is the most common way this integration fails silently.

Events to `/user/{id}/queue/map`:

- `blob.available` — a new blob is waiting. **Notification only, never the ciphertext**, so the socket stays cheap and the client controls when it decrypts
- `friend.availability.changed` — on edits, and on a scheduled sweep when someone crosses a window boundary
- `friend.pair.created` / `friend.pair.revoked`

The in-memory broker is correct for one instance and doesn't survive horizontal scaling — that's a Redis/RabbitMQ relay swap later, a config change rather than a redesign.

## 6. Build order

Each phase is independently demoable. Don't start one before the previous works end to end.

**Phase 0 — model prep.** `timeZoneId`, `publicKey`, `keyVersion` on `UserDocument`; `PUT /me/public-key`; accept `timeZoneId` in `/me/onboarding-complete`; index declarations. Small, but everything depends on it.

**Phase 1 — friend graph.** `FriendPairRepository` queries, `InviteCodeDocument` + repository, `FriendService` (mint, redeem, list, revoke, canonical ordering, self-pair and duplicate rejection), `FriendController`. Demo: two accounts pair via a code and see each other's public keys.

**Phase 2 — blob relay.** `EncryptedBlobRepository` with the upsert index, `BlobService` (friendship verification, size/rate caps), `BlobController`, fixed read DTOs. Demo: account A uploads ciphertext for B, B fetches and decrypts it.

**Phase 3 — availability fusion.** `AvailabilityEvaluator`, `GET /map/friends`. Demo: the free/busy status is correct across timezones.

**Phase 4 — realtime.** `WebSocketConfig`, STOMP auth interceptor, `/ws/**` exemption, `RealtimeEventPublisher`. Demo: A uploads, B's client is notified without polling.

**Phase 5 — optional depth.** APNs proximity alerts (note: these must be *computed on-device* and self-scheduled, since the server can't know who is near whom), meeting-midpoint suggestions negotiated client-side.

## 7. Testing

Unit tests following the existing `AuthServiceTest` Mockito pattern: `AvailabilityEvaluator` (timezone boundaries, midnight wrap, a busy segment covering the whole window, DST transitions), `FriendService` (canonical ordering, self-pair rejection, duplicate rejection, expired code, exhausted code), `BlobService` (upload to a non-friend rejected, upload to a revoked friend rejected, upsert replaces rather than appends).

Testcontainers Mongo for the genuinely database-dependent parts: the unique compound index rejecting a duplicate pair, the blob upsert index, and TTL actually expiring a blob.

Two security assertions worth writing by hand and keeping: **a non-friend can never upload a blob addressed to me**, and **revoking a pair deletes existing blobs in both directions**.

## 8. Config additions

```yaml
kismet:
  blobs:
    ttl-hours: 12
    max-ciphertext-bytes: 4096
    max-batch-size: 500
  friends:
    invite-code-ttl-minutes: 60
    max-friends: 500
```

## 9. Resolved decisions

1. **E2EE blob relay**, server blind to location. Availability stays plaintext so the server can still answer "who's free."
2. **Instant pairing** — redeeming a code creates an active pair with no approval step.

## 10. Still open

1. **Is location sharing symmetric** — must I upload blobs to see friends', or can I lurk?
2. **How coarse is "approximate" mode?** Blurring happens client-side pre-encryption; ~1.2 km hides your building but keeps the right neighborhood.
3. **Multi-device.** One key per user for v1; a second device currently means re-keying and orphaning in-flight blobs.
4. **Do we need background location for v1,** or is a foreground-only pin enough to demo? Background significantly changes the iOS entitlement story and can wait.
