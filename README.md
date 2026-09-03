# touchtips

When and where did I meet each person in my contacts. iOS 26, SwiftUI, on-device only.

Contacts stay the source of truth for *who*. touchtips owns *when* and *where*: it notices new contacts
through the contact store's change history, and gives each one a place from the visit that woke the app.
A Google Timeline export puts older contacts on the map. Confidence is carried on every answer and shown as a dot.

## Layout

```
project.yml                  XcodeGen spec; TouchTips.xcodeproj is generated, not committed
Packages/TouchTipsCore/      Records, schema (GRDB), resolver, ingest, queries, Timeline decoder. No UIKit.
Sources/TouchTips/           The app: capture (Contacts + CoreLocation), geocoder (MapKit), SwiftUI features
design/touchtips-v0.html     The design doc: screens, API lock-down, data model
```

## Build

Needs Xcode 26. From a shell with `just` and `xcodegen` (the flake's dev shell has both on macOS):

```
just gen     # writes TouchTips.xcodeproj; copies configs/Local.example.xcconfig to configs/Local.xcconfig on first run
just open    # opens it in Xcode
just test    # core package tests, no simulator needed
```

Set `DEVELOPMENT_TEAM` in `configs/Local.xcconfig` (gitignored) before building on a device.

## Permissions

Contacts, full access. Limited access cannot read change history.
Location, Always. Visit monitoring is the only thing that relaunches a terminated app, and a visit is how a new contact gets a place.

## Not in v0

Faces, calendar, any server, cross-device sync. See the design doc for what was cut and why.
