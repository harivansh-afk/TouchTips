# Contact-discovery latency: Shortcuts intent vs background location

Measured 2026-09-16 on the iOS 26.5 simulator (iPhone 17 Pro, Xcode 26.6, Debug builds,
`CODE_SIGNING_ALLOWED=NO`). Each build ran on its own fresh simulator, one at a time.

| Build | Commit | Background modes | Location grant |
| --- | --- | --- | --- |
| PR #58 (`feat/shortcuts-capture`) | `12978e8` | `fetch` | none |
| `main` (location) | `42ce1b1` | `location`, `fetch` | Always |

Contacts were added through Apple's Contacts app by an XCUITest harness that stamps timestamps into
the unified log under `sh.harivan.touchtips:bench`. App-side stamps come from the existing
`capture`/`notify` log lines, and process launch and suspension come from SpringBoard's
`Application process state changed` lines. The harness is not committed; it lived in
`Tests/TouchTipsUITests/BenchUITests.swift` for the run only.

## Results

Times are seconds between unified-log timestamps on the same simulator clock.

| Scenario | PR #58 (Shortcuts intent) | main (location) |
| --- | --- | --- |
| App running in background when the contact is saved: `CNContactStoreDidChange` → notification submitted | 0.40 (n=1) | 0.78 (n=1) |
| App terminated, wake → notification submitted | 1.03, 1.08 (n=2, from Shortcuts' launch request; includes cold launch) | 0.76 (n=1, from CoreLocation relaunch request) |
| App terminated, stationary: time until anything wakes it | trigger never fired on the simulator (2 attempts, 60 s and 45 s) | no wake in 40 s; unbounded without movement |
| App terminated, 3 km simulated move | n/a (no location) | move → relaunch 3.35, move → submitted 4.1 |
| Process suspended after the wake | 0.4 s after submission | stays resident while location session is active |

Timelines behind the numbers:

- PR, cold intent, sample 1: Shortcuts open request 10:51:24.871 → process running 24.954 →
  `tick intent: 3 new` 25.868 → first `notification submitted` 25.905 → suspended 26.312.
- PR, cold intent, sample 2: request 10:58:06.685 → running 06.763 → tick 07.724 → submitted 07.763
  → suspended 08.119.
- PR, backgrounded app: `contacts changed` 10:56:20.307 → `tick contacts: 1 new` 20.653 →
  submitted 20.707.
- main, backgrounded app: `contacts changed` 11:00:12.239 → `tick contacts: 1 new` 12.670 →
  `location enrichment completed` 12.832 → submitted 13.020.
- main, terminated + move: `simctl location set` 11:01:46.27 → SpringBoard open request 49.620 →
  running 49.703 → `tick movement: 1 new` 50.363 → submitted 50.384.

The Contacts app commits the record while the first name is being typed, about 1.5 s before Done
is tapped. Both builds' running-app path fired on that first change. The harness's "save → visible
in Notification Center" figure (about 4.5 s on both builds) is dominated by the test's own
Notification Center gesture and is not reported.

## What the simulator could not show

- The `Contacts` → `Is Closed` personal automation did not run the intent on the simulator, with
  Contacts backgrounded by Home and with Contacts terminated. No TouchTips launch, no Siri actions
  daemon activity that the log can render. The three contacts saved during those attempts were all
  discovered by the next manual run of the same automation (`tick intent: 3 new`), which confirms
  the intent path and shows the trigger never fired. Trigger latency on a real iPhone remains
  unmeasured.
- The intent path was exercised by tapping Run on the saved automation's shortcut in the Shortcuts
  app. That is the same `CheckContactsIntent.perform()` the trigger would invoke.
- The simulator's Shortcuts app crashed once (`WFAppSearchViewController`, `EXC_BAD_ACCESS`) when the
  app picker's search field was used. Scrolling the picker instead works. Not a TouchTips bug.
- Notification Center groups TouchTips notices into one cell; a matcher on the newest contact's name
  misses the group.

## Setup cost

Creating the automation on the simulator took 11 taps in Shortcuts: Automation → New Automation →
App → Choose → Contacts → ✓ → Is Closed → Run Immediately → Next → Create New Shortcut → search and
pick "Check for new contacts" → Done. iOS exposes no API for an app to create a personal automation,
and automations cannot be shared or imported, so every device needs this by hand. The old build
needed one Always-location prompt. The PR text is explicit about this trade.

## Reading the numbers

- Once TouchTips is running, both builds submit within a second of the Contacts change. The PR is
  faster because it no longer waits on a location fix, but n=1 each on a simulator.
- Terminated or suspended is the case that matters. The location build only wakes when CoreLocation
  delivers movement; stationary it never woke here or on the phone on 2026-09-09. The Shortcuts
  build wakes about 1 s after the trigger fires, but only if the user built the automation and only
  when Contacts itself is closed.
