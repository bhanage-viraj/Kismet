# PRD status — implemented vs remaining gaps

Snapshot against [`docs/PRD.md`](./PRD.md) after multi-branch gap closure work (Pulse receive, Focus, interestMatch E2EE, Live Activity accept, widget Accept Pulse).

**Overall:** Auth → Bump/invite friends → E2EE map pins → Presence States → Intelligence → **two-sided Pulse** → Focus gate → widgets/Siri is demoable. Background nearby needs Always permission; silent wake needs APNs credentials on deploy. Username search remains **cut** (invite codes).

---

## Feature status

| Feature | PRD tier | Status | What we implemented | Remaining gap |
|---|---|---|---|---|
| Onboarding + Sign in with Apple | P0 | **Done** | Apple → Spring JWT; interests + availability onboarding | Server still stores plaintext `appleSub` (PRD said hashed) |
| **Orbit Bump** | P0 | **Done** | Multipeer + UWB, consent UI, `POST /friends/pair`, Radar tab | Edge-case polish for live demo |
| **Presence States** | P0 | **Done (client E2EE)** | Four-state picker; sealed `mode` on LOCATION; Approximate grid; Eclipse hide | Friends Only = precise to whole friend graph (not a subset picker) |
| Friend list + who's nearby | P0 | **Done (demo) / Partial (durable)** | Map joins `/map/friends` + decrypted LOCATION | Durable locked-phone nearby needs Always + APNs ops |
| Remote friend-add (invite codes) | P1 | **Done** | Invite codes + QR | — |
| Username search friend-add | P1 | **Cut** | Invite codes replace this path | No `GET /users/search` planned |
| **Intelligence Layer** | P1 | **Near done** | Ranker → FM → suggestions; Focus filter gates `blocksSocial` | iOS 27 Dynamic Profiles gated on toolchain |
| Shared Interests | P1 | **Mostly done** | Onboarding + Profile; **E2EE `INTEREST_MATCH` blobs** + on-device intersection preferred | Server still stores plaintext interests for map fallback / onboarding |
| **Pulse** | P1 | **Done (two-sided)** | Send + server `PULSE` kind + inbox decrypt/expire/ack + map banner + silent wake | Presence/interest targeting polish optional |
| Widgets (static + Accept) | P1 / P2 | **Done** | Availability + map widgets; **Accept Pulse** on medium widget via App Intent | Copy less specific than PRD in some cases |
| Siri + App Intents | P1 | **Done (baseline)** | Who’s free/nearby; Draft/Confirm/Start Pulse; Focus filter intent | No iOS 27 richer App Schemas |
| Shared Live Activities | P2 | **Wired** | Starts on Pulse accept (Lock Screen / Dynamic Island) | Not shared across friends via push (`pushType: nil`) |
| Interactive widgets | P2 | **Done (Accept Pulse)** | Medium widget Accept button → App Group → app ack + Live Activity | — |
| MapKit spot suggestions | P2 | **Done** | `FindNearbyVenueTool` | Relies on model choosing the tool |
| Background location / proximity | Supports P0 | **Implemented (config-dependent)** | Always + significant-change + proximity alerts | Needs Always on device |
| Silent push wake | Supports P0 | **Implemented (ops-dependent)** | Token registry; LOCATION + PULSE wake | Needs `APNS_*` on deploy |
| Focus mode integration | Intelligence input | **Done** | `KismetFocusFilterIntent` + `FocusSocialGate` → ranker empty list | User must add Focus filter in Settings |
| E2EE blob relay + friends | Arch | **Mostly done** | JWT; `/blobs`; kinds include LOCATION / PULSE / INTEREST_MATCH | Interests/availability schedule still plaintext on user docs |

---

## Branch map (merge order)

Merge independently or stack Pulse first:

1. `feat/pulse-blob-kind` — server accepts `PULSE` + wake by kind  
2. `feat/pulse-inbox` — `IncomingPulse` + `PulseInboxStore`  
3. `feat/pulse-inbox-ui` — map banner + refresh + PULSE wake  
4. `feat/live-activity-accept` — Live Activity on Accept  
5. `feat/widget-accept-pulse` — widget Accept + App Group handoff  
6. `feat/focus-integration` — Focus filter (independent of Pulse)  
7. `feat/interest-match` — `INTEREST_MATCH` kind + seal/intersect (**resolve `BlobKind` with Pulse branch**: keep both `PULSE` and `INTEREST_MATCH`)  
8. `docs/prd-gaps-refresh` — this file  

Commits kept ≤ ~100 LOC each.

---

## Highest-priority remaining (ops / polish)

1. **Ops: APNs on deploy** — enable silent wake for stationary phones  
2. **Always location UX** — ensure onboarding copy prompts Always  
3. Optional: Pulse targeting by presence/interest; shared Live Activity push  

---

## Demo-readiness one-liner

**Bump + invite + auth + E2EE map + Presence + Intelligence + two-sided Pulse (inbox/accept/widget/Live Activity) + Focus filter + interestMatch blobs are coded; turn on APNs secrets for durable silent wake.**
