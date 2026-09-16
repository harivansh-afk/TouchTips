# Shortcuts-based contact discovery

## Scope

This replaces location-driven wakeups with a background App Intent and a user-configured personal
automation. It does not add a system-wide contact-save or NameDrop trigger. No server, extension,
shared container, new contact store, or database relocation is involved.

`AppRuntime.session` is shared by `AppDelegate` and `CheckContactsIntent`. The intent awaits the
existing coalesced Contacts history → transactional ingest/outbox → notification delivery operation.
Production ingest checks its expected history cursor transactionally and ignores historical location
evidence for new discoveries. Existing saved meetings and notes are retained. No scene, location fix,
photo fetch, or geocoding result is required to complete the action.

The intent supports background execution and permits invocation while locked. This does not bypass
Contacts permission, database file protection, or device execution policy. Failure leaves the cursor
and durable work available for the next eligible invocation. Do not weaken file protection to make
an unattended test pass. A successful action means the check completed; notification authorization,
Focus, Scheduled Summary, and transient delivery failure may leave a notice silent or pending.

## Install a development build

Use Xcode 26 on a Mac. From this branch, generate the project with `just gen`, configure your team
in the ignored `configs/Local.xcconfig`, then build/install with `just device`, or use Xcode's device
run destination. End the debugger session and launch the installed app normally before testing.
Do not uninstall the existing app to test an upgrade: that would erase the data whose preservation
we need to verify. Opening a PR alone does not put its build on TestFlight; the documented Xcode
Cloud workflow runs from `main`, so branch testing needs a local install or a separately configured
branch build. Do not merge solely to obtain a test build.

## Configure the phone

1. Open TouchTips → Settings → **Set up automatic checks** (also offered during onboarding).
2. Allow full Contacts access and notifications. The screen reads the existing address book
   silently as soon as Contacts is allowed; on upgrade the existing cursor is kept.
3. Tap **Open Shortcuts**. It opens the personal-automation trigger picker directly
   (`shortcuts://create-automation`, undocumented, with `shortcuts://` as the fallback).
4. In Shortcuts: **App** → **Choose** → **Contacts** → tick → **Is Closed** → **Run Immediately** →
   **Next** → **Check for new contacts**. The screen shows these five steps and a picture of the
   finished trigger. Do not add Open App, a location lookup, a wait loop, or Show Notification.
5. Save a throwaway contact in Contacts and go Home. Look for the TouchTips notification before
   reopening TouchTips, since opening the app also checks. The setup screen then shows
   **Working. Last check …**, which only a successful shortcut run updates.

iOS exposes no API to create, share, or import a personal automation, so the Shortcuts half is
always manual on iOS 26. On iOS 27 a shared shortcut carries its automation; see
[shortcuts-onboarding-research.md](shortcuts-onboarding-research.md) and
[shortcuts-onboarding-precedents.md](shortcuts-onboarding-precedents.md).

## Physical-device acceptance matrix

Record each result rather than assuming the simulator validates background execution.

| Scenario | Expected invariant / observation |
| --- | --- |
| First intent before baseline | Actionable setup error; no silent baseline that swallows the test contact |
| Contacts save → switch away | Intent runs, new record committed, notification submitted if allowed; app UI stays hidden |
| Phone save → switch away | Same; verify Phone picker availability and actual trigger behavior |
| Leave Contacts without changes | Successful check, no new notification |
| Repeat automation rapidly | No duplicate contacts/meetings; cursor never regresses |
| Multiple additions or account sync | Reconcile all additions; never claim app-close time is exact meeting time |
| App not running / force-quit | Measure invocation behavior separately; no debugger attached |
| Switch away and lock immediately | Measure action/Contacts/storage availability after first unlock |
| Reboot before first unlock | Unavailable protected data is a failure, not an empty replacement database |
| Notifications denied, Focus or Summary | Contact persists; submission is not evidence of banner presentation |
| Full → limited/denied Contacts access | No destructive snapshot or success timestamp; actionable permission recovery |
| NameDrop or save in another app | Not a direct trigger; addition may be found at the next check |
| Offline | Local discovery and notification do not need geocoding/network |
| Upgrade from location build | Existing notes, confirmed meetings, places, cursor and outbox preserved; old fence retired |
| Old open-ended visit | Must not assign its location to newly discovered contacts |
| Notification tap / in-app Add | Existing navigation, manual place selection and retry-safe contact creation still work |

Measure save time, intent start, history completion, commit, submission, and visible banner separately.
`lastNotice` starts at discovery and does not measure save-to-trigger latency. Compare battery over
longer real sessions before claiming savings; absence of location polling is not itself a measurement.

## Automated checks

- `just test`: core ingest, cursor/outbox rollback, snapshot/replay and location-evidence safeguards.
- `just check`: core tests and device build (requires signing).
- `just test-ios <dedicated-simulator-UUID>`: hosted and UI tests. Use an isolated simulator because
  the suites create contacts and change app permissions. The shortcut tests invoke the shared
  capture API; they do not emulate the actual system personal-automation scheduler.
- Inspect the generated app Info.plist: `UIBackgroundModes` must not contain `location`, and the
  Always-location usage description must be absent.

Validation results belong in the PR with the exact tested commit and command outputs. Do not mark
physical Shortcuts delivery or App Review acceptance verified based on compilation/unit tests alone.

## Review notes

For the next submission, explain that automatic contact checks are triggered by an optional,
user-created Shortcuts automation, and that background location is no longer declared or started.
Location is optional for explicit foreground place capture. Include setup and demonstration steps.
The old background-location documents remain historical; they are not the current feature contract.

## Apple references

- [App triggers, iOS 26](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/9.0/ios/26)
- [Personal automation setup](https://support.apple.com/guide/shortcuts/create-a-new-personal-automation-apdfbdbd7123/9.0/ios/26)
- [Background App Intent modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [App Shortcuts exposure](https://developer.apple.com/documentation/appintents/app-shortcuts)
- [Contacts change history](https://developer.apple.com/documentation/technotes/tn3149-fetching-change-history-events)
