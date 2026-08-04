# Bump / Radar — two-device demo rehearsal

Real devices only for Multipeer + UWB. Simulator validates UI/codec, not discovery or ranging.

## Happy path (opening demo beat)

1. Deploy / point both phones at the same Spring backend (`APPLE_VERIFY_TOKEN` as needed for Sign in with Apple).
2. Cold launch both apps → Sign in with Apple (two different accounts).
3. Both open the **Radar** tab → **Start Bump**.
4. Grant **Local Network** and **Bluetooth** when prompted (Settings → indeKismet if previously denied).
5. Each phone should list the other under Nearby → both **tap to Bump**.
6. Expect: key exchange → radar distance updates (direction if UWB + pose allow) → “You’re friends now”.
7. More → Friends: both see each other; `connectedVia` should be `BUMP` (via `GET /friends`).

Backend check without UI:

```bash
BASE_URL=https://your-api ./scripts/smoke-bump.sh
```

## Chaos passes (must stay recoverable)

| Scenario | Expected |
|---|---|
| Background / switch apps mid-browse | Session cancels; “Come back and tap Bump again”; Start over works |
| Decline incoming invite | Returns to Nearby list; can tap again |
| Invite timeout | One automatic retry, then “tap to try again” |
| Kill one app mid-range | Other shows connection lost; Start over |
| Airplane / no cell during persist | Initiator shows retry save; **Retry save** calls `POST /friends/pair` even if MC is dead |
| Already friends | Skips persist; still offers Radar if UWB works |
| Leave Radar tab | Ceremony stops (`onDisappear`); Start Bump again from idle |

## Invite / redeem regression (must not break)

Remote pairing is unchanged:

1. More → Friends → Create invite code on phone A.
2. Redeem on phone B.
3. Both appear in Friends with `connectedVia: INVITE_CODE`.

Or: `BASE_URL=… ./scripts/smoke-friends.sh`

## Device notes

- UWB / direction: iPhone 11+ with compatible peers; distance-only is success, not failure.
- Both on same Wi‑Fi **and** BT-only (Wi‑Fi off) once each before the live demo.
- Fresh install: Local Network prompt must appear on first Bump — if discovery is empty, check Settings first.
