# Orbit — Product Requirements Document
**Build with WWDC26 Hackathon | Team size: 2–3 | Target: Live demo on real devices**

> Orbit doesn't help you keep track of your friends — it helps you make time for them.

---

## 1. Problem Statement

People we care about most are often nearby, but we only realize it after the chance to meet has passed. Location-sharing apps show *where* friends are, but not whether they're free, what they're doing, or when it's the right moment to reach out. Coordinating spontaneous plans still relies on "Where are you?" / "Are you free?" texts, and busy schedules hide the small windows where everyone could actually meet.

## 2. Solution

**Orbit** is a privacy-first social presence platform that helps friends reconnect at the right place and the right time. It should feel like **Apple Calendar + Find My + Apple Intelligence, focused on friendship** — not Find My + Instagram. There is no feed, no posting, no content. Every surface answers one of two questions: *"who's around and free right now?"* and *"what can I join right now?"*

## 3. Core Features & Priority Tiers

| Tier | Feature | Status | Notes |
|---|---|---|---|
| **P0** | Onboarding + Sign in with Apple | **Done** | Custom auth via Spring backend, not iCloud-account-as-identity. Plaintext `appleSub` still stored (see gaps). |
| **P0** | **Orbit Bump** — in-person friend discovery, one-tap mutual consent | **Done** | Hero friend-add path; Multipeer + UWB + server bump pair. |
| **P0** | **Presence States** — Available / Friends Only / Approximate / Eclipse (hidden) | **Done (client E2EE)** | Map picker; sealed `mode` on LOCATION; Approximate fuzz; Eclipse hide; Friends Only subset allowlist (precise to chosen friends). Schedule FREE/BUSY is calendar fallback only. |
| **P0** | Friend list + "who's nearby and available" view | **Done (demo) / Partial (durable)** | Map + E2EE LOCATION; Always + APNs needed for locked-phone durability. |
| **P1** | Invite codes / QR — fallback friend-add for people not physically together | **Done** | Replaces username search. Secondary path; Bump is the hero flow. Same Spring pairing + TOFU public-key exchange. |
| **P1** | Username search | **Cut** | Not shipping — use invite codes instead. |
| **P1** | **Intelligence Layer** — Foundation Models reasoning over calendar, Focus, time, location, motion, interests, meetup history → proactive suggestions | **Near done** | Ranking-then-model + Focus gate; iOS 27 Dynamic Profiles still toolchain-gated. Full design: `Kismet Apple Intelligence Engine — Technical Design`. |
| **P1** | **Shared Interests** — onboarding picks, opt-in sync | **Mostly done** | Onboarding + Profile + E2EE `INTEREST_MATCH`; server still keeps plaintext interests for fallback. |
| **P1** | **Pulse** — lightweight, auto-expiring invitation, shown only to relevant friends by presence/availability/interest | **Done (two-sided)** | Publish / inbox / expire / ack / map banner / widget Accept / Live Activity on accept; send gated by presence + interest. |
| **P1** | Widgets (static) — "Bala is nearby, free until 4:15 PM" | **Done** | App Group snapshot cache; availability + map + meetup surfaces. |
| **P1** | Siri + App Intents — "Who's free nearby?", "Anyone up for coffee?" | **Done (baseline)** | 26.4-compatible baseline shipped; richer Siri AI schemas remain iOS 27-gated. |
| **P2** | **Shared Live Activities** — starts once a meetup is accepted; Dynamic Island, live ETA, arrival notification, auto-ends | **Done (shared)** | Dual-start via sealed `MEETUP` blob; ActivityKit push tokens; peer ContentState via APNs (`APNS_*` for remote ETA). |
| **P2** | Interactive widgets (accept a Pulse directly from the widget) | **Done** | Medium widget Accept Pulse via App Intent + App Group handoff. |
| **P2** | MapKit spot suggestions inside Intelligence Layer output | **Done** | `FindNearbyVenueTool` grounds venue suggestions in MapKit. |

**Removed entirely:** Moments, Stories, Likes, Comments, Feeds, any content/engagement mechanics, and **username search** (invite codes are the remote friend-add path). Orbit's strength is coordination, not content.

Recommendation: core P0 + first-class P1 (Pulse, widgets, Intelligence baseline) are on `main`. Remaining risk is **ops and rehearsal**, not missing features — see [`docs/PRD_GAPS.md`](./PRD_GAPS.md).

## 4. System Architecture — Spring backend, end-to-end encrypted relay

```
iOS App (SwiftUI)                          Spring Boot API Server (Kotlin/Java)
- Orbit Bump (nearby discovery)             - Auth (Sign in with Apple -> JWT)
- Foundation Models (Intelligence Layer)     - Friend pairing (public-key exchange
- CryptoKit (E2EE)                             relay only, keys generated on-device)
- Core Location / Motion                    - Blob relay: stores/forwards ciphertext
- EventKit, Focus status                       only, cannot decrypt payloads
- App Intents / Siri                        - Push notification token registry
- WidgetKit, Live Activities                - Real-time delivery (WebSocket)
- MapKit

                                             MongoDB / relational store (Spring-managed)
                                               - Account records (id, hashed Apple ID)
                                               - Public keys per friend pairing
                                               - Encrypted blobs (ciphertext + routing
                                                 metadata only, short TTL)
```

**No CloudKit.** The team evaluated a CloudKit/CKShare-based architecture and explicitly decided against migrating — the shipped Spring backend with JWT auth and CryptoKit end-to-end encryption is the architecture of record going forward. This section supersedes any earlier CloudKit-based draft of this PRD.

**Privacy model, unchanged in spirit from the encrypted-relay design:** public keys are exchanged directly between two devices at pairing time (via Orbit Bump's local session, or relayed once through the Spring server for the invite-code / QR path, matching Signal/WhatsApp's trust-on-first-use model). Every subsequent payload — presence updates, Pulses, meetup invites — is encrypted client-side with CryptoKit before it ever reaches the server. The Spring backend stores and routes ciphertext plus minimal routing metadata (sender ID, recipient ID, timestamp); it cannot read any of it, and blobs are deleted shortly after confirmed delivery.

**Foundation Models reasoning stays entirely on-device** (or, optionally, on Private Cloud Compute for specific redacted draft-copy generation on iOS 27 — never with raw coordinates or friend identities). The Spring backend never sees calendars, location history, or any of the context the Intelligence Layer reasons over — only the small, deliberate encrypted output (a presence label, a Pulse) passes through it, and even then only as ciphertext.

## 5. Data Model (Spring-managed store)

**Account**
```
id, hashedAppleId, pushToken, createdAt
```

**FriendPairKey** (created once at pairing — Bump or invite code)
```
id, userA, userB, userAPublicKey, userBPublicKey,
connectedVia: "orbitBump" | "inviteCode",
status: "pending" | "accepted", createdAt
```

**EncryptedBlob** (the only "content" record — opaque to the server)
```
id, senderId, recipientId, ciphertext,
kind: "presence" | "pulse" | "interestMatch" | "meetupInvite" | "meetup",
createdAt (short TTL, deleted on confirmed delivery)
```

~~**PublicUsername**~~ — **cut** with username search; not part of the shipping data model.

Notes:
- Presence, Pulse content, and interest tags are all generated, reasoned about (via Foundation Models), and encrypted entirely on-device before ever becoming an `EncryptedBlob`.
- A full breach of the Spring database exposes account IDs, public keys, and ciphertext — nothing readable about any user's presence, interests, or plans.

## 6. Core API Endpoints (REST + WebSocket, Spring)

| Method | Route | Purpose |
|---|---|---|
| POST | `/auth/apple` | Exchange Apple identity token for app JWT |
| POST | `/friends/invite` (+ redeem) | Invite-code / QR remote friend-add — returns pairing material only |
| POST | `/friends/pair` | Register a new pairing (Bump or invite path) — stores both public keys |
| POST | `/friends/:id/accept` | Confirm mutual pairing |
| GET | `/friends` | List friend IDs + public keys (client decrypts everything else locally) |
| POST | `/blobs` | Push an encrypted blob to a recipient — server never inspects payload |
| GET | `/blobs/pending` | Pull undelivered blobs addressed to me |

~~`GET /users/search?username=`~~ — **cut**; not shipping.

WebSocket events: `blob:delivered` (forwards ciphertext + kind + sender only), `friend:request`.

## 7. Intelligence Layer — summary (full design in the linked engineering doc)

Foundation Models reasoning is **proactive suggestion ranking with grounded facts, not a chatbot.** Deterministic providers (location, calendar free/busy, Focus, motion, interests, meetup history) feed a cheap ranking pass; only the top 1–3 candidates ever reach the model, which handles narrative phrasing, venue choice (via a MapKit tool), and CTA wording through strongly-typed `@Generable` output — never free-text parsing. If the model is unavailable, a deterministic fallback keeps the map from ever looking broken. Deployment stays on the current OS baseline (**26.4**) with iOS 27 features gated: **Dynamic Profiles** agent (meetup Spotlight search → venue → Pulse draft copy, **no Private Cloud Compute**) and `SpotlightSearchTool` compile under the iOS 27 / Swift 6.4 toolchain and run only when the OS supports them; older devices keep the single-session path. Soft interest suggestions are inferred locally from hangout categories and require an explicit user Accept.

## 8. Open Questions / Risks
- **Presence States** — client publish/enforce shipped; keep both demo devices on a build that seals `mode` so Eclipse/Approximate behave end-to-end.
- **Orbit Bump** — shipped for v1; keep demo reliability polish in mind (BT/LAN/UWB).
- **Key management on reinstall** — losing/reinstalling means re-pairing with friends unless private keys are backed up via iCloud Keychain; likely fine for a hackathon demo, worth stating explicitly rather than assuming.
- **Invite-code trust model** — weaker than Bump's in-person key exchange (server briefly introduces the two public keys); same TOFU class as the old username-search idea; optional fingerprint/verification code remains a stretch hardening item.
- **App Intents / Spotlight boundaries** — be explicit about what Orbit contributes to the system-wide semantic index; an Eclipse-hidden friend's presence should never surface via Siri/Spotlight even indirectly.
- **Silent wake / Always location** — code is present; deploy APNs credentials and grant Always on demo phones or durable “who's nearby” degrades when apps are suspended.
- Cut order if still behind on polish: `appleSub` hashing → drop plaintext interests.

## 9. Next Steps
1. Keep [`docs/PRD.md`](./PRD.md) + [`docs/PRD_GAPS.md`](./PRD_GAPS.md) as the living status source of truth.
2. Ops: APNs secrets on deploy for silent proximity wake (`APNS_*` — see `server/.env.example`).
3. Confirm Always location on both demo devices; rehearse locked-phone nearby.
4. Full two-device demo rehearsal (Bump → presence → Intelligence → Pulse → widget → Siri).
5. Optional polish only: hash `appleSub`; drop plaintext interests once INTEREST_MATCH is universal.