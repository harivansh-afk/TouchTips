# TouchedTips

When and where did we meet?
This is a question i often ask myself since i meet so many people on a daily basis. 
I tried sending selfies to the people i find interesting, but this doesnt scale
I can name 5 times off the top of my head when i needed something from a person i met at some point of time but could not find their name on my phone.

Contacts stay the source of truth for *who*. TouchedTips owns *when* and *where*: it notices new contacts
through the contact store's change history, and gives each one a place from the visit that woke the app.
A Google Timeline export puts older contacts on the map. Confidence is carried on every answer and shown as a dot.

## Layout

```
project.yml                  XcodeGen spec; TouchedTips.xcodeproj is generated, not committed
Packages/TouchedTipsCore/      Records, schema (GRDB), resolver, ingest, queries, Timeline decoder. No UIKit.
Sources/TouchedTips/           The app: capture (Contacts + CoreLocation), geocoder (MapKit), SwiftUI features
design/TouchedTips-v0.html     The design doc: screens, API lock-down, data model
```

## Build

Needs Xcode 26. From a shell with `just` and `xcodegen` (the flake's dev shell has both on macOS):

```
just gen     # writes TouchedTips.xcodeproj; copies configs/Local.example.xcconfig to configs/Local.xcconfig on first run
just open    # opens it in Xcode
just test    # core package tests, no simulator needed
just check   # the gate before a PR: core build and tests, then a device build where any warning fails
just lint    # swiftformat in lint mode; `just fmt` fixes what it reports
```

`just check` and `just lint` run locally before a PR. github.com/harivansh-afk/TouchedTips is the canonical repo, because Xcode Cloud builds from it: every push to `main` archives and goes to TestFlight, with `ci_scripts/ci_post_clone.sh` generating the project on the runner and stamping the build number. git.harivan.sh holds a read-only mirror that `.github/workflows/mirror.yml` refreshes on every push.

Set `DEVELOPMENT_TEAM` in `configs/Local.xcconfig` (gitignored) before building on a device.

## Permissions

Contacts, full access. Limited access cannot read change history.
Location, Always. Visit monitoring is the only thing that relaunches a terminated app, and a visit is how a new contact gets a place.

## Not in v0

Faces, calendar, any server, cross-device sync. See the design doc for what was cut and why.
