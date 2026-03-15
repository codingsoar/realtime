# Lock Exit Ad QA Report Template

## Report Info
- Date:
- Tester:
- Build/Commit:
- App Version:
- Branch:
- Target Screen: `lib/screens/solo_study_screen.dart`
- Related Checklist: `docs/LOCK_EXIT_AD_QA_CHECKLIST.md`

## Test Environment
- Device:
- OS Version:
- Network Condition:
- Ad Unit Type (test/prod):

## Summary
- Total Cases:
- Passed:
- Failed:
- Blocked:
- Key Risk:

## Case Results
| Case ID | Scenario | Result (Pass/Fail/Blocked) | Notes |
|---|---|---|---|
| C1 | Basic unlock with 1 ad |  |  |
| C2 | Multi-ad progress update |  |  |
| C3 | Reward not earned |  |  |
| C4 | Ad load/show failure |  |  |
| C5 | Remaining time live update |  |  |
| C6 | Lock expiry while popup open |  |  |
| C7 | Navigation/back handling |  |  |
| C8 | Session reset between lock runs |  |  |
| R1 | Non-lock mode regression smoke |  |  |

## Failure Details (Fill for each Fail)
### Failure #1
- Case ID:
- Severity: Critical / High / Medium / Low
- Frequency: Always / Intermittent / Rare
- Expected:
- Actual:

### Reproduction Steps
1. 
2. 
3. 

### Reproduction Data
- Required Ads (`N`):
- Watched Ads before issue:
- Lock Remaining at issue:
- Popup state (open/closed):
- Network state:

### Logs
- App log snippet:
```text
[timestamp] ...
```
- Ad callback sequence:
```text
onAdLoaded ->
onUserEarnedReward ->
onAdDismissedFullScreenContent
```
- Error stack (if any):
```text
...
```

### Evidence
- Screenshot path:
- Screen recording path:

### Impact
- User impact:
- Scope estimate:
- Workaround:

## Open Issues / Follow-up
1. 
2. 

## Sign-off
- QA Owner:
- Dev Owner:
- Decision: Release / Fix Required / Re-test Required
