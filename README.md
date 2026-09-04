# TouchedTips

When and where did we meet?
This is a question i often ask myself since i meet so many people on a daily basis. 
I tried sending selfies to the people i find interesting, but this doesnt scale
I can name 5 times off the top of my head when i needed something from a person i met at some point of time but could not find their name on my phone.

Contacts stay the source of truth for *who*. TouchedTips owns *when* and *where*: it stays resident on a
low-power location session so a new contact is heard the moment it is saved, takes one precise fix, and
tells you who you just met and where. Visits, a breadcrumb fence and significant-change monitoring bring it
back when iOS kills it. A Google Timeline export puts older contacts on the map. Confidence is carried on
every answer and shown as a dot. `design/capture-v1.html` is the capture architecture.

## Layout

```
project.yml                  XcodeGen spec; TouchedTips.xcodeproj is generated, not committed
Packages/TouchedTipsCore/      Records, schema (GRDB), resolver, ingest, queries, Timeline decoder. No UIKit.
Sources/TouchedTips/           The app: capture (Contacts + CoreLocation), geocoder (MapKit), SwiftUI features
design/TouchedTips-v0.html     The design doc: screens, API lock-down, data model
design/capture-v1.html         The capture architecture: presence, relaunch net, the tick, notification, measurement
```

## Build

Needs Xcode 26. From a shell with `just` and `xcodegen` (the flake's dev shell has both on macOS):

```
just gen     # writes TouchedTips.xcodeproj; copies configs/Local.example.xcconfig to configs/Local.xcconfig on first run
just open    # opens it in Xcode
just test    # core package tests, no simulator needed
just check   # the gate before a PR: core build and tests, then a device build where any warning fails
just lint    # swiftformat in lint mode; `just fmt` fixes what it reports
just device  # build for the plugged-in iPhone and install it, no debugger attached
just log     # stream the app's log lines from that iPhone; the capture path logs every stage with timings
```

`just check` and `just lint` run locally before a PR. github.com/harivansh-afk/TouchedTips is the canonical repo and PRs merge there; git.harivan.sh keeps a read-only pull mirror. Builds ship through Xcode Cloud: every push to `main` archives and goes to TestFlight, with `ci_scripts/ci_post_clone.sh` generating the project on the runner and stamping the build number. The workflow itself is configured in App Store Connect, not here.

Set `DEVELOPMENT_TEAM` in `configs/Local.xcconfig` (gitignored) before building on a device.

## Permissions

Contacts, full access. Limited access cannot read change history.
Location, Always. Keeps the process resident, and location events are the only thing that relaunches it when it is not.
Notifications. Optional; everything still records without them.

## Not in v0

Faces, calendar, any server, cross-device sync. See the design doc for what was cut and why.

## Agents

Donot use forgejo as SOT, for this repo Github is the source of truth and
forgejo is a read-only mirror
