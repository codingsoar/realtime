# Lock Exit Ad QA Checklist

## Scope
- Feature: early-exit popup during lock mode
- Rule: popup auto-closes when watched ads reach selected required count
- Screen: `lib/screens/solo_study_screen.dart`

## Environment
- Android real device (required)
- iOS real device (recommended)
- Network:
  - Normal
  - Unstable/offline (for ad load failure path)

## Test Matrix
- Required ad count: `1`, `3`, `5`
- Lock duration: short (`1-3 min`) and medium (`10+ min`)

## Case 1: Basic unlock with one ad
1. Start lock mode with required ads `1`.
2. Trigger early-exit popup.
3. Tap ad button and finish ad reward flow.

Expected:
- Counter text updates to `1 / 1` immediately after reward callback.
- Popup closes automatically.
- Lock mode is released.
- Unlock snackbar appears once.

## Case 2: Multi-ad progress update
1. Start lock mode with required ads `3`.
2. Open early-exit popup.
3. Complete first rewarded ad.
4. Complete second rewarded ad.
5. Complete third rewarded ad.

Expected:
- Popup stays open after ad 1 and ad 2.
- Counter text updates in place: `1 / 3`, then `2 / 3`.
- No duplicate popup instances appear.
- On ad 3 completion: popup auto-closes and lock releases.

## Case 3: Reward not earned
1. Start lock mode with required ads `3`.
2. Open early-exit popup.
3. Start ad and close before reward condition is met.

Expected:
- Counter does not increase.
- Popup remains usable.
- Lock does not release.

## Case 4: Ad load/show failure
1. Force poor network or ad load failure condition.
2. Tap ad button in early-exit popup.

Expected:
- Failure path returns without crash/freeze.
- User sees retry guidance (snackbar).
- Retry can recover when network is back.

## Case 5: Remaining lock time live update while popup open
1. Start lock mode with `2+` minutes.
2. Open early-exit popup and keep it open for 15+ seconds.

Expected:
- Remaining lock time shown in popup decreases continuously.
- UI remains responsive.

## Case 6: Lock expires while popup open
1. Start lock mode with very short duration.
2. Open early-exit popup and wait until lock naturally expires.

Expected:
- Lock release flow completes safely.
- No stuck dialog state.
- No duplicate snackbar flood.

## Case 7: Navigation/back handling
1. During lock mode, press system back.
2. Tap popup cancel.
3. Press back again.

Expected:
- Early-exit popup appears consistently.
- Cancel closes only the popup.
- App does not unexpectedly exit.

## Case 8: Session reset between lock runs
1. Complete unlock flow in lock session A.
2. Start lock session B with a different required ad count.
3. Open early-exit popup.

Expected:
- Counter starts from `0 / N` for session B.
- Previous session progress is not leaked.

## Regression Smoke
- Non-lock mode exit popup still works.
- Study timer start/stop still works.
- No crash on repeated ad attempts.

## Record Template
- Device / OS:
- Build commit:
- Case ID:
- Result: Pass / Fail
- Notes:
