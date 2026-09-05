# Notification reliability

The capture path is local: Contacts history → SQLite contact/meeting/outbox transaction →
UNUserNotificationCenter → delegate → People navigation. No server participates.

## Failure modes addressed

- A real simulator notification response crashed in UIKit state restoration with `NSInternalInconsistencyException: Call must be made on main thread`. The async delegate's generated completion ran on a background thread after `MainActor.run` returned. The delegate now uses an explicit completion handler and calls it on the main actor with the action handler.
- Contact discovery previously advanced its history token before trying a notification once. Submission errors, missing permission, or termination during place lookup lost the alert permanently. Pending notices now survive in SQLite and retry on wakes and authorization.
- In-app Add created the person before the listener saw it; the listener skipped that known ID, so no notification was posted. Add now queues in its own database transaction.
- Debouncing cancelled the task even after scanning had begun. Debounce now owns only the delay; one active task serializes scans and drains any wake received during a scan. Background expiration cancels the active work, and the location request cooperates with cancellation.
- Place lookup required network responses before posting. It now runs separately; a notification uses the place name already available at submission.
- History reset events were ignored, retaining deleted contacts and outdated names. Snapshot reconciliation now removes absent contacts and their pending notices, updates names, and preserves surviving IDs' notes and meetings.
- Notification destinations could render no content for a missing row. Person screens now show explicit loading, unavailable, and failure states. Notification navigation waits for readiness, uses no row zoom, dismisses relevant sheets, and consumes pending routes after onboarding.
- Unknown and dismissal actions previously opened a person. Only the default tap and Fix navigate.

## Automated checks

Core tests run with `nix develop -c just test`. They cover first-run silence, new and exact additions,
atomic rollback of contact/token/outbox on a forced database failure, queue persistence after reopening,
replay deduplication, snapshot reconciliation, and deletion/Not a meeting cleanup.

Create a dedicated simulator so test contacts and notification permissions are isolated:

```sh
xcrun simctl create 'TouchTips Notifications' 'iPhone 17 Pro' 'iOS26.5'
xcrun simctl boot <returned-uuid>
nix develop -c just test-ios <returned-uuid>
```

Use an installed runtime/device type from `xcrun simctl list` if these names differ. Do not run the
suite against a personal device. The test target requires full Contacts access and reports a skip if
it is missing; a release validation must have zero skipped tests.

Hosted app tests save a real organization-only contact through `CNContactStore`, wait for the real
`CNContactStoreDidChange` observer to ingest it without a manual scan, and remove that test contact.
They also inject notification permission/submission failures, verify retry and acknowledgement,
and check action handling and route replacement.

UI tests submit real local notifications through the production queue and tap them in Notification
Center using its Open action. They check a warm open from Map, Back, a terminated-app open, and an
open after the person was deleted. Another test creates a uniquely named contact in Apple's Contacts
app, returns to TouchTips for catch-up, and opens its notification. That contact remains only in the
dedicated simulator. UI fixtures seed a separate SQLite database under `NotificationTests/<session>`; they do
not simulate the notification delegate. The fixture is compiled only for Debug simulators. The
fixture session persists in that simulator to support actual SpringBoard cold launches.

Xcode writes screenshots, failures, and results to `build/notification-tests/Logs/Test/*.xcresult`.
Open the result bundle in Xcode for UI failures. A successful build is not evidence that taps worked.

## Physical iPhone release check

Validation on September 5, 2026, using the dedicated iPhone 17 Pro simulator on iOS 26.5:

- `nix develop -c just check`: 41 core tests and the signed device build passed, with no build warnings.
- Six hosted app tests passed, including actual Contacts observation, concurrent wakes, denial/retry, and response routing. No skips.
- Four UI cases passed: warm open from Map and Back, cold open, deleted-contact fallback, and Apple Contacts save → foreground catch-up → notification → person.
- All 25 changed Swift files passed formatting lint. Full-repository lint still fails on 31 untouched files; the original `main` checkout fails on 46 files with this toolchain. Unrelated formatting changes were excluded.

Result bundles from this run are under the main checkout's `build/notification-tests/Logs/Test/`:
`Test-TouchTips-2026.09.05_11-13-03--0400.xcresult` (warm),
`Test-TouchTips-2026.09.05_11-13-46--0400.xcresult` (six app tests, cold, deleted), and
`Test-TouchTips-2026.09.05_11-15-28--0400.xcresult` (external Contacts app).

Simulator tests do not reproduce suspension, Core Location relaunch, NameDrop, battery policy,
Focus, Scheduled Summary, or real lock-screen delivery. Before release, install a device build and
disconnect the debugger; a debugger can keep a process running that would normally suspend.

1. Grant full Contacts and notifications; launch once and wait for the initial snapshot. Existing contacts must remain silent.
2. Add a uniquely named contact in Apple's Contacts app. Confirm one record, one notification, its tap destination, and Back. Repeat with in-app Add and NameDrop.
3. Repeat while TouchTips is foregrounded, backgrounded, and the phone is locked. Record the save, discovery, and submission times separately. With no location permission or network, capture and notification must still work when the app runs; the place may be unknown.
4. Disable notifications, create a contact, and open TouchTips to capture it. Re-enable notifications and reopen TouchTips: the queued notice should submit once. Repeat with Contacts denied/limited then restored to full access.
5. Keep a delivered notification, terminate TouchTips, and tap it. Repeat from Map, Search, Settings, an existing person, and after deleting the referenced contact. Each must open the correct person or a visible unavailable screen, with working Back.
6. Test That's right, Fix, Not a meeting, and dismissal. Confirm only tap/Fix navigate and the other actions persist the expected meeting state.
7. Leave the device idle and exercise movement/visit wakes. Separately force-quit it, create a contact, and reopen it: catch-up should occur. Immediate background detection after force-quit is not a supported promise.

Both known iPhones were unavailable to this Mac during validation on September 5, 2026. These checks remain a
release gate; simulator success alone is insufficient to sign off background behavior.

## Limits

Apple queues process notifications while an app is suspended; contact changes are not a guaranteed
wake mechanism. Location and background refresh execution are discretionary. See Apple's
[queued notification lifecycle](https://developer.apple.com/documentation/uikit/processing-queued-notifications),
[background location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background),
and [Contacts history reset semantics](https://developer.apple.com/documentation/contacts/cnchangehistorydropeverythingevent).

Successful notification submission does not establish banner display. User notification settings,
Focus and summaries control presentation. The outbox provides retryable submission with stable IDs,
not an atomic transaction across iOS and SQLite: if a process dies after submission and the user then
clears that notification before reconciliation, a retry can show it again. There is no system receipt
API that makes exactly-once visible alerts possible across that gap.

An existing contact first exposed by permission expansion, account sync, or a history reset cannot
be distinguished from a newly created contact by this app. First access establishes a silent baseline;
later unknown IDs are discoveries, not proof of a new meeting or its exact time. Historic notification
failures from versions without an outbox cannot be reconstructed safely and are not backfilled.
