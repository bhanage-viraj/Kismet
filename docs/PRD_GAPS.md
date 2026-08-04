# PRD status — implemented vs remaining gaps

Snapshot against [`docs/PRD.md`](./PRD.md) after Presence States end-to-end + earlier `feat/radar` work (Orbit Bump, background proximity, silent push wake).

**Overall:** Auth → Bump/invite friends → E2EE map pins → **Presence States (publish + enforce)** → Intelligence → Pulse *send* → widgets/Siri is demoable. **Pulse as a two-sided loop** is the largest remaining product gap. Background nearby is implemented in code but needs APNs credentials on the deployed server to wake stationary phones.

---

## Feature status

| Feature | PRD tier | Status | What we implemented | Remaining gap |
|---|---|---|---|---|
| Onboarding + Sign in with Apple | P0 | **Done** | Apple → Spring JWT; interests + availability onboarding | Server still stores plaintext `appleSub` (PRD said hashed); no push-token-on-user-doc (tokens live in `push_tokens`) |
| **Orbit Bump** | P0 | **Done** | Multipeer + UWB ranging, consent UI, `POST /friends/pair` bump path, Radar tab, `docs/BUMP_DEMO.md`, smoke script | Edge-case polish (BT/LAN prompts, UWB device limits) for live demo reliability |
| **Presence States** (Available / Friends Only / Approximate / Eclipse) | P0 | **Done (client E2EE)** | Four-state picker + `PresenceModeStore`; sealed `mode` in LOCATION blobs; Approximate ~500 m grid; Eclipse publish + hide on receive; map/detail/proximity/Intelligence use `presenceState`; schedule FREE/BUSY is calendar fallback only | Separate `presence` blob kind / server-side presence document not needed for demo (mode rides on LOCATION). Friends Only = precise to friends (already the blob audience) |
| Friend list + who's nearby & available | P0 | **Done (demo) / Partial (durable)** | Friend list; map joins `/map/friends` + decrypted LOCATION blobs | “Nearby while locked” depends on Always + significant-change + (optional) APNs — see Background location below |
| Remote friend-add (invite codes) | P1 | **Done** | Invite codes + QR (`POST /friends/invite` + redeem) | — |
| Username search friend-add | P1 | **Cut** | **Not shipping** — invite codes replace this path | No `GET /users/search?username=` / `PublicUsername` planned |
| **Intelligence Layer** | P1 | **Near done for demo** | Ranker → Foundation Models `@Generable` → `SuggestionStore`; calendar/location/motion/friends; fallback composer; MapKit venue tool | Focus stub; meetup history is local/learning only |
| Shared Interests | P1 | **Partial** | Onboarding interests → `POST /me/interests`; server intersection on map; ranker signal | Interests plaintext on `UserDocument`; no E2EE `interestMatch` blobs / opt-in sync as PRD described |
| **Pulse** | P1 | **Partial** | `PulsePublisher` seals `PULSE` blobs with expiry; CTA from suggestions / Siri | **No inbox / UI for incoming Pulses**; presence/interest targeting not wired; client doesn’t ack blobs; server may not accept `PULSE` kind yet |
| Widgets (static) | P1 | **Done** | Friend availability + map widgets via App Group / `SuggestionSnapshotWriter` | Copy less specific than PRD “free until 4:15 PM” in all cases |
| Siri + App Intents | P1 | **Done (baseline)** | Who’s free/nearby, Start Pulse; Eclipse guard on entities | No iOS 27 richer schemas; intents need a prior app refresh for live store data |
| Shared Live Activities | P2 | **Scaffold / deferred** | Controllers + entitlements exist | `start(...)` not wired from meetup-accept; not shared across friends |
| Interactive widgets | P2 | **Missing / deferred** | Static widgets + deep links only | No Accept Pulse from home-screen widget |
| MapKit spot suggestions | P2 (pulled forward) | **Done** | `FindNearbyVenueTool` in the model session | Relies on the model choosing the tool |
| **Background location / proximity** | Supports P0 nearby | **Implemented (config-dependent)** | Always upgrade; significant-location monitoring; `BackgroundProximityController`; ~800 m local alerts; presence-aware copy; sharing survives leaving the map tab | Needs **Always** permission on device; neighborhood-scale accuracy only |
| **Silent push wake** | Supports P0 nearby | **Implemented (ops-dependent)** | `POST/DELETE /push/token`; APNs silent push on LOCATION upload; iOS `remote-notification` wake → decrypt + proximity | Needs teammate to set `APNS_*` on deploy (`.p8` never in git). Apple may throttle silent pushes |
| Focus mode integration | Intelligence input | **Stub** | `FocusContextProvider` + ranker gate on `blocksSocial` | Always `blocksSocial: false`; no `SetFocusFilterIntent` / real Focus status |
| E2EE blob relay + friends (server) | Arch | **Mostly done** | JWT auth; CryptoKit; `/blobs` + pending + STOMP; bump + invite pairing | Interests/availability schedule still plaintext; pending/accept handshake unused (pairs go ACTIVE); blob ack unused on iOS |

---

## What landed recently

### Presence States (complete on client)
1. **Map header picker** — Available / Friends Only / Approximate / Eclipse  
2. **`PresenceModeStore`** — persisted selection drives publishes  
3. **E2EE `mode` on LOCATION payloads** — sealed with coords; legacy blobs fall back to schedule FREE/BUSY/UNKNOWN  
4. **Approximate** — ~500 m grid before seal; receivers show “Nearby” / no precise ETA  
5. **Eclipse** — still publishes a mode blob so friends hide the pin immediately; filtered from map / ranking / proximity / Siri surfaces  
6. **You-pin feedback** — presence-tinted label + ripple on change  
7. Map chrome cleanup — removed unused filter button + location chevron  

### Earlier (`feat/radar`)
1. **Orbit Bump** — full in-person pairing ceremony + server bump pair API  
2. **Background proximity** — Always + significant location change + on-device nearby notifications  
3. **Silent APNs wake** — token registry + LOCATION-triggered content-available push (disabled until env configured)  

---

## Highest-priority remaining gaps (for the PRD story)

1. **Pulse receive + visibility** — inbox, expire, target by presence/interest (not send-only); fix server blob kind if needed  
2. **Focus integration** — real Focus so the Intelligence Layer doesn’t suggest during DND-like states  
3. **Ops: APNs on deploy** — enable silent wake so stationary phones get proximity without waiting for significant-change  
4. **Live Activities wiring** (P2) — only if meetup-accept demo needs Dynamic Island  

---

## Built outside / diverged from PRD

| Item | Notes |
|---|---|
| Invite-code / QR pairing | **Canonical remote friend-add** — username search is cut |
| Presence `mode` on LOCATION | PRD sketched a separate `presence` blob kind; shipping mode inside LOCATION is enough for demo |
| WeatherKit map overlay | Not in PRD |
| Meetup memory / learned ranking | Beyond PRD summary |
| Immediate ACTIVE friendships | No pending → accept handshake |
| Blob kinds | `LOCATION` / `PULSE` (and others) vs PRD `presence` / `pulse` / `interestMatch` / `meetupInvite` |
| Product naming | Code/bundle often “Kismet” / “indeKismet”; PRD says Orbit |

---

## Open PRD risks — current read

| PRD risk | Status |
|---|---|
| Presence States = top priority fix | **Closed for client demo** — picker + publish + enforce shipped |
| Orbit Bump ownership / timeline | **Closed** for v1 — implemented |
| Key management on reinstall | Still open (Keychain local; no iCloud Keychain backup called out) |
| Username-search trust model | **N/A — path cut**; invite codes are the remote TOFU path |
| App Intents / Eclipse leakage | Guards coded; live Eclipse now hides on receive when both clients are current |
| Background location for nearby | Code landed; Always UX + APNs ops remain |

---

## Demo-readiness one-liner

**Bump + invite add + auth + E2EE map + Presence States + Intelligence + widgets + Siri baseline are demoable; two-sided Pulse is the biggest remaining PRD miss. Background nearby works with Always; silent wake needs APNs secrets on the server.**
