# PRD status — implemented vs remaining gaps

Snapshot against [`docs/PRD.md`](./PRD.md) on **`main`** (after PRs #17–#25: Pulse stack, Focus, interestMatch E2EE, Live Activity accept, widget Accept Pulse, Apple cold-start harden).

**Overall:** Auth → Bump/invite friends → E2EE map pins → Presence States → Intelligence → **two-sided Pulse** → Focus gate → widgets/Siri is **on main and demoable**. Background nearby needs Always permission; silent wake needs `APNS_*` on deploy. Username search remains **cut** (invite codes).

---

## Feature status

| Feature | PRD tier | Status | What we implemented | Remaining gap |
|---|---|---|---|---|
| Onboarding + Sign in with Apple | P0 | **Done** | Apple → Spring JWT; interests + availability onboarding; cold-start retry harden | Server still stores plaintext `appleSub` (PRD said hashed) |
| **Orbit Bump** | P0 | **Done** | Multipeer + UWB, consent UI, `POST /friends/pair`, Radar tab | Edge-case polish for live demo (BT/LAN/UWB) |
| **Presence States** | P0 | **Done (client E2EE)** | Four-state picker; sealed `mode` on LOCATION; Approximate grid; Eclipse hide; **Friends Only subset picker** (precise to allowlist, Eclipse hide for others) | — |
| Friend list + who's nearby | P0 | **Done (demo) / Partial (durable)** | Map joins `/map/friends` + decrypted LOCATION; background proximity locally | Durable locked-phone nearby needs Always + APNs ops |
| Remote friend-add (invite codes) | P1 | **Done** | Invite codes + QR; pairs go **ACTIVE** immediately | No `POST /friends/:id/accept` (PRD table outdated; not needed for demo) |
| Username search friend-add | P1 | **Cut** | Invite codes replace this path | No `GET /users/search` planned |
| **Intelligence Layer** | P1 | **Near done** | Ranker → FM → suggestions; Focus filter gates `blocksSocial` | iOS 27 Dynamic Profiles gated on toolchain |
| Shared Interests | P1 | **Mostly done** | Onboarding + Profile; **E2EE `INTEREST_MATCH` blobs** + on-device intersection preferred | Server still stores plaintext interests for map fallback / onboarding |
| **Pulse** | P1 | **Done (two-sided)** | Send + inbox/expire/ack + map banner + silent wake + widget Accept; **presence/interest targeting** at send | — |
| Widgets (static + Accept) | P1 / P2 | **Done** | Availability + map widgets; **Accept Pulse** on medium widget via App Intent | Copy less specific than PRD in some cases |
| Siri + App Intents | P1 | **Done (baseline)** | Who’s free/nearby; Draft/Confirm/Start Pulse; Focus filter intent | No iOS 27 richer App Schemas |
| Shared Live Activities | P2 | **Done (shared)** | Dual-start via sealed `MEETUP` on accept; ActivityKit `pushType: .token`; peer ContentState via APNs liveactivity | Needs `APNS_*` for remote ETA sync |
| Interactive widgets | P2 | **Done (Accept Pulse)** | Medium widget Accept → App Group → app ack + Live Activity | — |
| MapKit spot suggestions | P2 | **Done** | `FindNearbyVenueTool` | Relies on model choosing the tool |
| Background location / proximity | Supports P0 | **Implemented (config-dependent)** | Always + significant-change + proximity alerts | Needs Always on device |
| Silent push wake | Supports P0 | **Implemented (ops-dependent)** | Token registry; LOCATION + PULSE wake | Needs `APNS_*` on deploy (`APNS_ENABLED` defaults false) |
| Focus mode integration | Intelligence input | **Done** | `KismetFocusFilterIntent` + `FocusSocialGate` → ranker empty list | User must add Focus filter in Settings |
| E2EE blob relay + friends | Arch | **Mostly done** | JWT; `/blobs`; kinds include LOCATION / PULSE / INTEREST_MATCH / **MEETUP** | Interests/availability schedule still plaintext on user docs |

---

## Merged gap-closure work (historical)

All of the following landed on `main` (no further merge order required):

1. `feat/pulse-blob-kind` — server `PULSE` + wake by kind  
2. `feat/pulse-inbox` — `IncomingPulse` + `PulseInboxStore`  
3. `feat/pulse-inbox-ui` — map banner + refresh + PULSE wake  
4. `feat/live-activity-accept` — Live Activity on Accept  
5. `feat/widget-accept-pulse` — widget Accept + App Group handoff  
6. `feat/focus-integration` — Focus filter  
7. `feat/interest-match` — `INTEREST_MATCH` + seal/intersect (both `PULSE` and `INTEREST_MATCH` in `BlobKind`)  
8. `docs/prd-gaps-refresh` — prior gaps snapshot  

---

## Highest-priority remaining (ops / polish)

1. **Ops: APNs on deploy** — set `APNS_ENABLED` + key material per [`server/.env.example`](../server/.env.example); enable silent wake + Live Activity peer ETA sync  
2. **Always location UX** — ensure onboarding / Settings path prompts Always (code already requests it)  
3. Optional harden: hash `appleSub`; drop plaintext interests once INTEREST_MATCH is universal  

**Out of PRD / not shipping:** contacts sync, discovery feeds, chat (map “Say Hi” / “Message” still toast “coming soon”), account deletion, server-side proximity (impossible against ciphertext).

**Doc debt:** [`docs/MAP_BACKEND_PLAN.md`](./MAP_BACKEND_PLAN.md) still describes empty stubs — ignore; live APIs are in [`docs/API.md`](./API.md).

---

## Demo-readiness one-liner

**Bump + invite + auth + E2EE map + Presence (Friends Only subset) + Intelligence + two-sided Pulse (inbox/accept/widget/Live Activity shared) + Focus filter + interestMatch blobs are on `main`; turn on APNs secrets for durable silent wake + peer Live Activity ETA, then rehearse two-device flow.**
