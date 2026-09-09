# TouchTips

When and where did we meet?
This is a question i often ask myself since i meet so many people on a daily basis. 
I tried sending selfies to the people i find interesting, but this doesnt scale
I can name 5 times off the top of my head when i needed something from a person i met at some point of time but could not find their name on my phone.

Contacts stay the source of truth for *who*. TouchTips records *when* and *where* a new contact was
discovered. It checks on launch, foreground activation, contact changes while running, and available
background wakes. A solid dot means a user-confirmed meeting; a hollow dot means a suggestion.
Contacts without meeting details have no dot. Date precision and missing places are shown separately.

Swipe right on a person to open their note, ready to type. Swipe left to forget their TouchTips
meeting details and note, with confirmation; the phone contact is retained. These native, icon-only
swipes follow Mixbridge's TrackRow pattern and work in the People list, timeline, and search.

Changing one field confirms only that field. "Confirm meeting" accepts the entire record, including
any unknown place. Existing edits are preserved on upgrade; older records whose confirmation cannot
be established remain suggestions until reviewed. Automatic location matches retain the discovery
interval. Point locations are considered only for intervals of at most 60 seconds, and current fixes
are requested only for recent contact-change callbacks. Callbacks can be delayed by suspension;
only the last successful Contacts read establishes the beginning of a discovery interval.

## How it works

iOS does not provide a contact-save wake mechanism for a suspended or terminated app. Background
location and refresh are additional opportunities to scan; they cannot guarantee continuous execution.

1. A retained Contacts store reads change history. Contact-change bursts coalesce for 300 ms; launch, foreground and location wakes request an immediate scan. A finite background assertion begins in the callback, before any debounce, and covers the shared scan, delivery and bounded retries. Concurrent wakes share one scan task, with a follow-up scan for changes received during it. Transient failures retry after two and five seconds, then retain the cursor for a later wake.
2. First access silently snapshots existing contacts. Later additions are resolved against available visits and saved immediately. Optional location enrichment runs independently, bounded to eight seconds, and can improve an unconfirmed meeting afterward. History resets reconcile names and deletions while retaining notes and meetings for surviving IDs. Failed history enumeration returns no partial events or new cursor.
3. The contact, meeting, history token, and pending notification commit in one SQLite transaction. An in-app Add queues through the same table. A failed transaction advances none of them.
4. Notification delivery retries queued records on wakes and after authorization, with two bounded retries for transient failures. One failing record does not block the others. All concurrent callers wait for the shared delivery; removed notices are rechecked before submission. Location and place naming cannot block submission. A stable request ID reconciles notifications already pending or delivered after a process interruption. SQLite acknowledges successful submission, not proof that iOS displayed a banner.
5. Taps wait for the active scene, onboarding, and the People navigation stack. They replace the People path without a zoom transition. Missing or unreadable contacts have visible fallback screens and a Back action.
6. Background refresh requests become eligible after fifteen minutes, while preserving an earlier pending request. This is a request to iOS, not a polling interval or delivery guarantee. Expiration cancels the shared scan and ends its background assertion immediately.

In-app Add retains the saved system-contact identity if its SQLite write fails. A retry updates that
contact and preserves the original meeting time. The selected place, meeting, and pending notice
commit together. Notes flush when the scene becomes inactive; diagnostic heartbeat history retains
seven days.

Continuous background location is established from the foreground, or a significant-change callback,
with coarse accuracy and the visible iOS location indicator. Each delivered location callback offers
a Contacts check, including cached or imprecise fixes. The persisted geofence stays observed while
locked; an absent initial fence gets one bounded location request without delaying notifications.
See the [background wake repair](docs/background-wake-repair.md) for the specific Apple guidance,
device experiments and validation limits.

See the [September 8 architecture review](docs/architecture-review-2026-09-08.md) for findings,
regression coverage, and the remaining physical-device verification boundary.

See [notification testing](docs/notification-testing.md) for automated checks, device release checks,
and remaining platform limitations. The older `docs/design/capture-v1.html` describes the original design.

See [regular-use simulator QA](docs/qa-2026-09-05.md) for isolated fixtures, regression coverage,
before/after evidence, open review PRs, and checks still needed before release.

Everything stays on the phone. `docs/design/capture-v1.html` has the reasoning, failure modes and build order.

## Layout

```
project.yml                    XcodeGen spec; TouchTips.xcodeproj is generated, not committed
Packages/TouchTipsCore/         Records, schema (GRDB), resolver, ingest, queries, Timeline decoder. No UIKit.
Sources/TouchTips/              The app: capture (Contacts + CoreLocation), geocoder (MapKit), SwiftUI features
docs/design/TouchTips-v0.html    The design doc: screens, API lock-down, data model
docs/design/capture-v1.html      The capture architecture: presence, relaunch net, the tick, notification, measurement
```

## Build

Needs Xcode 26. From a shell with `just` and `xcodegen` (the flake's dev shell has both on macOS):

```
just gen     # writes TouchTips.xcodeproj; copies configs/Local.example.xcconfig to configs/Local.xcconfig on first run
just open    # opens it in Xcode
just test    # core package tests, no simulator needed
just check   # the gate before a PR: core build and tests, then a device build where any warning fails
just lint    # swiftformat in lint mode; `just fmt` fixes what it reports
just device  # build for the plugged-in iPhone and install it, no debugger attached
just log     # stream the app's log lines from that iPhone; the capture path logs every stage with timings
```

`just check` and `just lint` run locally before a PR. github.com/harivansh-afk/TouchTips is the canonical repo and PRs merge there; git.harivan.sh keeps a read-only pull mirror. Builds ship through Xcode Cloud: every push to `main` archives and goes to TestFlight, with `ci_scripts/ci_post_clone.sh` generating the project on the runner and stamping the build number. The workflow itself is configured in App Store Connect, not here.

Set `DEVELOPMENT_TEAM` in `configs/Local.xcconfig` (gitignored) before building on a device.

## Permissions

Contacts, full access. Limited access cannot read change history.
Location, Always. Allows background location events that offer additional chances to discover contacts.
Notifications. Optional; everything still records without them.

## Not in v0

Faces, calendar, any server, cross-device sync. See the design doc for what was cut and why.

## Agents

Donot use forgejo as SOT, for this repo Github is the source of truth and
forgejo is a read-only mirror
