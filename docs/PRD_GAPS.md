# PRD status — implemented vs remaining gaps

Snapshot against [`docs/PRD.md`](./PRD.md) on branch **`feat/prd-gaps-shared-la-targeting-friends-only`** (PRs #17–#25 on `main`, plus shared LA / Pulse targeting / Friends Only subset / LA End).

**Overall:** Auth → Bump/invite friends → E2EE map pins → Presence States → Intelligence → **two-sided Pulse** → Focus gate → widgets/Siri is **demoable**. Background nearby needs Always permission; silent wake + peer LA ETA need `APNS_*` on deploy. Username search remains **cut** (invite codes).

Legend: ✅ done · ⚠️ partial / ops · ❌ cut · ⬜ exists but not fully wired

---

## Feature status

| | Feature | PRD tier | Status | What we implemented | Remaining gap |
|---|---|---|---|---|---|
| ✅ | Onboarding + Sign in with Apple | P0 | **Done** | Apple → Spring JWT; interests + availability onboarding; cold-start retry harden | ⬜ Server still stores plaintext `appleSub` (PRD said hashed) |
| ✅ | **Orbit Bump** | P0 | **Done** | Multipeer + UWB, consent UI, `POST /friends/pair`, Radar tab | Edge-case polish for live demo (BT/LAN/UWB) |
| ✅ | **Presence States** | P0 | **Done (client E2EE)** | Four-state picker; sealed `mode`; Approximate; Eclipse; **Friends Only subset picker** | — |
| ⚠️ | Friend list + who's nearby | P0 | **Done (demo) / Partial (durable)** | Map + E2EE LOCATION; background proximity locally | ⬜ Always UX + APNs for locked-phone durability |
| ✅ | Remote friend-add (invite codes) | P1 | **Done** | Invite codes + QR; pairs go **ACTIVE** immediately | ⬜ Deep link `kismet://pair` not handled in app |
| ❌ | Username search friend-add | P1 | **Cut** | Invite codes replace this path | No `GET /users/search` planned |
| ⚠️ | **Intelligence Layer** | P1 | **Near done** | Ranker → FM → suggestions; Focus filter gates `blocksSocial` | ⬜ iOS 27 Dynamic Profiles toolchain-gated |
| ⚠️ | Shared Interests | P1 | **Mostly done** | Onboarding + Profile; E2EE `INTEREST_MATCH` + on-device intersect | ⬜ Plaintext interests still on server; INTEREST_MATCH not silent-woken |
| ✅ | **Pulse** | P1 | **Done (two-sided)** | Send + inbox/expire/ack + banner + widget Accept; **presence/interest targeting** | — |
| ✅ | Widgets (static + Accept) | P1 / P2 | **Done** | Availability + map widgets; Accept Pulse via App Intent | ⬜ Widget deep links (`kismet://…`) not handled |
| ✅ | Siri + App Intents | P1 | **Done (baseline)** | Who’s free/nearby; Draft/Confirm/Start Pulse; Focus filter | Needs warm suggestion store; no iOS 27 schemas |
| ✅ | Shared Live Activities | P2 | **Done (shared)** | Dual-start `MEETUP`; ActivityKit push; **End button + auto-end** at meetAt | ⬜ Peer ETA sync needs `APNS_*` |
| ✅ | Interactive widgets | P2 | **Done (Accept Pulse)** | Medium widget Accept → App Group → app ack + Live Activity | — |
| ✅ | MapKit spot suggestions | P2 | **Done** | `FindNearbyVenueTool` | Relies on model choosing the tool |
| ⚠️ | Background location / proximity | Supports P0 | **Implemented (config-dependent)** | Always + significant-change + proximity alerts | ⬜ Always UX / Settings recovery |
| ⚠️ | Silent push wake | Supports P0 | **Implemented (ops-dependent)** | Token registry; LOCATION + PULSE + MEETUP wake | ⬜ `APNS_ENABLED` defaults false |
| ✅ | Focus mode integration | Intelligence input | **Done** | `KismetFocusFilterIntent` + `FocusSocialGate` | User must add filter in Settings |
| ⚠️ | E2EE blob relay + friends | Arch | **Mostly done** | JWT; `/blobs`; LOCATION / PULSE / INTEREST_MATCH / MEETUP | Interests/availability schedule still plaintext |

---

## Completed checklist (recent gap closures)

- [x] Pulse blob kind + silent wake by kind
- [x] Pulse inbox decrypt / expire / ack
- [x] Pulse map banner + PULSE wake
- [x] Live Activity starts on Pulse accept
- [x] Widget Accept Pulse + App Group handoff
- [x] Focus filter → Intelligence gate
- [x] E2EE `INTEREST_MATCH` seal / intersect
- [x] Friends Only subset allowlist (precise to chosen friends; Eclipse hide for others)
- [x] Pulse send targeting by presence / interest
- [x] Shared Live Activity dual-start via sealed `MEETUP` + ActivityKit push tokens
- [x] Live Activity **End** control + auto-end at `meetAt` (+ grace) / max lifetime
- [x] PRD / API docs refresh for the above

---

## Exists but not fully wired

### Ops / demo (code ready)

| | Item | Exists | Missing to finish |
|---|---|---|---|
| ⬜ | **APNs deploy** | `PushWakeService`, `LiveActivityPushService`, client token registrars | Set `APNS_ENABLED=true` + key material ([`server/.env.example`](../server/.env.example)) |
| ⬜ | **Always location UX** | `requestAlwaysAuthorizationIfNeeded`, background proximity | Onboarding / Profile status + re-prompt if dismissed |
| ⬜ | **URL / deep links** | `WidgetDeepLink` (`kismet://friend|meetup|pulse/accept|home`); invite `kismet://pair?code=` | `onOpenURL` + `CFBundleURLTypes`; QR / widget taps open generically today |

### Visible UI / incomplete loops

| | Item | Exists | Missing to finish |
|---|---|---|---|
| ⬜ | **Say Hi / Message** | Buttons on `PersonDetailView` | Still toast “coming soon” (chat **out of PRD**) |
| ⬜ | **Map pin CTA copy** | “Say hi nearby” / “Ping a friend” | Not a send path; Intelligence CTA *does* send Pulse |
| ⬜ | **Widget / Siri cold path** | Accept + Draft/Confirm intents | Need warm inbox / suggestion store; deep-link accept unused |
| ⬜ | **Focus filter setup** | Intent + gate wired | User must add filter in **Settings → Focus** (no in-app guide) |
| ⬜ | **INTEREST_MATCH wake** | Client seal/load | Server wakes LOCATION / PULSE / MEETUP only — not INTEREST_MATCH |
| ⬜ | **Mutual friends row** | UI on person card | Live path hardcodes `0` |

### Dead / unused server surfaces

| | Item | Notes |
|---|---|---|
| ⬜ | Blob kinds `AVAILABILITY`, `MESSAGE` | Enum only — no client seal/consume |
| ⬜ | `PUT /me/timezone` | No iOS caller (timezone via onboarding-complete) |
| ⬜ | `GET /map/friends/{id}` | Client uses list endpoint only |
| ❌ | `POST /friends/:id/accept` | Never needed — invite/Bump go ACTIVE immediately |

### Privacy harden (optional)

| | Item | Notes |
|---|---|---|
| ⬜ | Hash `appleSub` | PRD data model; still plaintext |
| ⬜ | Drop plaintext interests | Once INTEREST_MATCH is universal + woken |

### OS-gated (fine to leave)

| | Item | Notes |
|---|---|---|
| ⬜ | iOS 27 Dynamic Profiles + `SpotlightSearchTool` | Written; runs only on iOS 27 / Swift 6.4 toolchain |

### Out of PRD / not shipping

Contacts sync, discovery feeds, chat, account deletion, server-side proximity, username search.

**Doc debt:** [`docs/MAP_BACKEND_PLAN.md`](./MAP_BACKEND_PLAN.md) still describes empty stubs — ignore; live APIs are in [`docs/API.md`](./API.md).

---

## Merged gap-closure work (historical)

Landed on `main` (PRs #17–#25):

1. `feat/pulse-blob-kind` — server `PULSE` + wake by kind  
2. `feat/pulse-inbox` — `IncomingPulse` + `PulseInboxStore`  
3. `feat/pulse-inbox-ui` — map banner + refresh + PULSE wake  
4. `feat/live-activity-accept` — Live Activity on Accept  
5. `feat/widget-accept-pulse` — widget Accept + App Group handoff  
6. `feat/focus-integration` — Focus filter  
7. `feat/interest-match` — `INTEREST_MATCH` + seal/intersect  
8. `docs/prd-gaps-refresh` — prior gaps snapshot  

On this branch:

9. Friends Only subset + Pulse targeting + shared `MEETUP` LA + LA End / auto-end  

---

## Highest-priority remaining

1. **Ops: APNs on deploy** — silent wake + peer Live Activity ETA  
2. **Always location UX** — prompt / Settings recovery  
3. **Deep links** — handle `kismet://` for invite QR + widgets  
4. Optional: INTEREST_MATCH wake; hide or Pulse-wire Say Hi; privacy harden  

---

## Demo-readiness one-liner

**Bump + invite + auth + E2EE map + Presence (Friends Only subset) + Intelligence + two-sided Pulse (inbox/accept/widget/shared LA + End) + Focus filter + interestMatch are implemented; turn on APNs, grant Always, avoid Say Hi/Message toasts, rehearse two-device flow.**
