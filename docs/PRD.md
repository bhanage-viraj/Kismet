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
| **P0** | Onboarding + Sign in with Apple | — | Custom auth via Spring backend, not iCloud-account-as-identity. |
| **P0** | **Orbit Bump** — in-person friend discovery, one-tap mutual consent | Separate workstream, not yet built | Must be flawless live — opening demo beat. Tracked outside the Intelligence Engine milestone; confirm owner/timeline explicitly. |
| **P0** | **Presence States** — Available / Friends Only / Approximate / Eclipse (hidden) | **Gap** — code currently only has free/busy/unknown | Four-state model is a distinctive brand element; Intelligence is currently gated on the old binary enum until this lands. Flag as a priority fix, not a nice-to-have. |
| **P0** | Friend list + "who's nearby and available" view | — | Minimum viable coordination loop. |
| **P1** | Username search — fallback friend-add for people not physically together | — | Secondary path; Bump is the hero flow. Routed through the Spring backend, same as Bump-established pairs. |
| **P1** | **Orbit Intelligence** — Foundation Models reasoning over calendar, Focus, time, location, motion, interests, meetup history → proactive suggestions | In progress — see linked engineering design | Ranking-then-model architecture; grounded, `@Generable` structured output only. Full technical design: `Kismet Apple Intelligence Engine — Technical Design`. |
| **P1** | **Shared Interests** — onboarding picks, opt-in sync | — | Feeds Orbit Intelligence ranking and Pulse targeting. |
| **P1** | **Pulse** — lightweight, auto-expiring invitation, shown only to relevant friends by presence/availability/interest | Elevated to first-class (was suggestion-copy-only) | Needs a real publish/expire/visibility path, not just a CTA string — this is now required, not stretch. |
| **P1** | Widgets (static) — "Bala is nearby, free until 4:15 PM" | Elevated from stretch to P1 | Primary surface outside the app itself; backed by a shared App Group cache, not live model calls. |
| **P1** | Siri + App Intents — "Who's free nearby?", "Anyone up for coffee?" | Baseline via AppIntentsProvider works on current OS; richer Siri AI schema matching is iOS 27-gated | Ship the 26.4-compatible baseline first; layer entity schemas if demo devices are on iOS 27. |
| **P2** | **Shared Live Activities** — starts once a meetup is accepted; Dynamic Island, live ETA, arrival notification, auto-ends | Deferred | Cuttable without breaking the core story. |
| **P2** | Interactive widgets (accept a Pulse directly from the widget) | Deferred | Polish on top of P1 static widgets. |
| **P2** | MapKit spot suggestions inside Orbit Intelligence output | Pulled forward as a Tool the model can call | Grounds venue suggestions in real MapKit results rather than model-invented places — strong demo value for modest cost. |

**Removed entirely:** Moments, Stories, Likes, Comments, Feeds, and any content/engagement mechanics. Orbit's strength is coordination, not content.

Recommendation: build strictly top-down. Don't start P1 Intelligence work until Orbit Bump + Presence States + friend list run live on two physical devices — Intelligence has nothing real to reason over without them.

## 4. System Architecture — Spring backend, end-to-end encrypted relay

```
iOS App (SwiftUI)                          Spring Boot API Server (Kotlin/Java)
- Orbit Bump (nearby discovery)             - Auth (Sign in with Apple -> JWT)
- Foundation Models (Orbit Intelligence)     - Friend pairing (public-key exchange
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

**Privacy model, unchanged in spirit from the encrypted-relay design:** public keys are exchanged directly between two devices at pairing time (via Orbit Bump's local session, or relayed once through the Spring server for the username-search path, matching Signal/WhatsApp's trust-on-first-use model). Every subsequent payload — presence updates, Pulses, meetup invites — is encrypted client-side with CryptoKit before it ever reaches the server. The Spring backend stores and routes ciphertext plus minimal routing metadata (sender ID, recipient ID, timestamp); it cannot read any of it, and blobs are deleted shortly after confirmed delivery.

**Foundation Models reasoning stays entirely on-device** (or, optionally, on Private Cloud Compute for specific redacted draft-copy generation on iOS 27 — never with raw coordinates or friend identities). The Spring backend never sees calendars, location history, or any of the context Orbit Intelligence reasons over — only the small, deliberate encrypted output (a presence label, a Pulse) passes through it, and even then only as ciphertext.

## 5. Data Model (Spring-managed store)

**Account**
```
id, hashedAppleId, pushToken, createdAt
```

**FriendPairKey** (created once at pairing — Bump or username search)
```
id, userA, userB, userAPublicKey, userBPublicKey,
connectedVia: "orbitBump" | "usernameSearch",
status: "pending" | "accepted", createdAt
```

**EncryptedBlob** (the only "content" record — opaque to the server)
```
id, senderId, recipientId, ciphertext,
kind: "presence" | "pulse" | "interestMatch" | "meetupInvite",
createdAt (short TTL, deleted on confirmed delivery)
```

**PublicUsername** (for the search fallback only — not personal)
```
username (unique, indexed), accountId
```

Notes:
- Presence, Pulse content, and interest tags are all generated, reasoned about (via Foundation Models), and encrypted entirely on-device before ever becoming an `EncryptedBlob`.
- A full breach of the Spring database exposes account IDs, public keys, and ciphertext — nothing readable about any user's presence, interests, or plans.

## 6. Core API Endpoints (REST + WebSocket, Spring)

| Method | Route | Purpose |
|---|---|---|
| POST | `/auth/apple` | Exchange Apple identity token for app JWT |
| GET | `/users/search?username=` | Look up a user by username — returns ID + public key only |
| POST | `/friends/pair` | Register a new pairing (Bump or username path) — stores both public keys |
| POST | `/friends/:id/accept` | Confirm mutual pairing |
| GET | `/friends` | List friend IDs + public keys (client decrypts everything else locally) |
| POST | `/blobs` | Push an encrypted blob to a recipient — server never inspects payload |
| GET | `/blobs/pending` | Pull undelivered blobs addressed to me |

WebSocket events: `blob:delivered` (forwards ciphertext + kind + sender only), `friend:request`.

## 7. Orbit Intelligence — summary (full design in the linked engineering doc)

Foundation Models reasoning is **proactive suggestion ranking with grounded facts, not a chatbot.** Deterministic providers (location, calendar free/busy, Focus, motion, interests, meetup history) feed a cheap ranking pass; only the top 1–3 candidates ever reach the model, which handles narrative phrasing, venue choice (via a MapKit tool), and CTA wording through strongly-typed `@Generable` output — never free-text parsing. If the model is unavailable, a deterministic fallback keeps the map from ever looking broken. Deployment stays on the current OS baseline with iOS 27 features (multi-step agentic profiles, Private Cloud Compute drafting) gated behind availability checks so the demo degrades gracefully on older devices and gets a fuller experience on newer ones.

## 8. Open Questions / Risks
- **Presence States gap is the top priority fix** — Intelligence, Pulse targeting, and the core brand pitch (Eclipse mode etc.) all depend on the four-state model existing; until then everything is reasoning over a binary free/busy stand-in.
- **Orbit Bump timeline** — confirm this is actively owned; without it there's no real friend graph for Intelligence or Pulse to demo against.
- **Key management on reinstall** — losing/reinstalling means re-pairing with friends unless private keys are backed up via iCloud Keychain; likely fine for a hackathon demo, worth stating explicitly rather than assuming.
- **Username-search trust model** — weaker than Bump's in-person key exchange (server briefly introduces the two public keys); consider an optional fingerprint/verification code as a stretch hardening item.
- **App Intents / Spotlight boundaries** — be explicit about what Orbit contributes to the system-wide semantic index; an Eclipse-hidden friend's presence should never surface via Siri/Spotlight even indirectly.
- 2–3 people, ~2 weeks — if behind schedule, cut order is: Shared Live Activities → interactive widgets → MapKit tool grounding → Presence four-state (last resort only, since it's foundational, not cosmetic).

## 9. Next Steps
1. Sync this PRD into `docs/PRD.md` in the repo as the single source of truth (currently empty).
2. Close the Presence States gap (four-state model) before further Intelligence work depends on it.
3. Confirm Orbit Bump ownership and timeline as its own workstream.
4. Build out the encrypted blob relay endpoints on the Spring backend (Section 6) if not already complete.
5. Wire the Orbit Intelligence pipeline per the linked engineering design: context providers → ranker → Foundation Models → `SuggestionStore`.
6. Elevate Pulse to a real publish/expire/visibility path wired to the Intelligence suggestion CTA.
7. Ship static widgets (P1) off the shared `SuggestionStore` cache.
8. App Intents + Shortcuts baseline, iOS-27-gated schema enhancements if demo devices support it.
9. Buffer + full two-device demo rehearsal (Bump → presence → Intelligence → Pulse → widget → Siri).