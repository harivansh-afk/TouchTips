# TouchTips

When and where did we meet?
This is a question i often ask myself since i meet so many people on a daily basis. 
I tried sending selfies to the people i find interesting, but this doesnt scale
I can name 5 times off the top of my head when i needed something from a person i met at some point of time but could not find their name on my phone.

Contacts stay the source of truth for *who*. TouchTips owns *when* and *where*: it stays resident on a
low-power location session so a new contact is heard the moment it is saved, takes one precise fix, and
tells you who you just met and where. Visits, a breadcrumb fence and significant-change monitoring bring it
back when iOS kills it. A Google Timeline export puts older contacts on the map. Confidence is carried on
every answer and shown as a dot. `docs/design/capture-v1.html` is the capture architecture.

## How it works

iOS never wakes a suspended app for a contact change, so the app stays awake instead. Everything else follows from that.

1. **Presence.** Once Location is Always, a low-power location session (3 km accuracy, no GPS, pausing off) keeps the process resident. It is the only reason the add is an event rather than something found later.
2. **Event.** The resident process receives `CNContactStoreDidChange` the moment a contact is saved. One save fires several; a 300 ms coalesce turns them into one tick.
3. **Tick.** One function for every wake source: diff the contact store since the last change-history token, take one precise one-shot fix if there is an add, resolve the add against visits (a fix is a zero-length visit and outranks any stay), name the place (nearby business, else street), post the notification, save the token, re-drop the fence. Idempotent, so any path can run it any number of times.
4. **Notification.** Local, one per new person: "You just met Alice Chen" over "Blue Bottle @ 2:14 pm", with That's right, Fix, and Not a meeting. Tapping opens the person.
5. **Relaunch net.** When iOS kills the process, visits, significant-change monitoring, a 150 m breadcrumb geofence around the last fix, and a background refresh floor bring it back. The add is caught then, with the place you were inside as an inferred answer.
6. **Measure.** Every wake and a five-minute pulse write a heartbeat row. Dev in Settings turns it into uptime, wakes by source, battery per hour, and the last add-to-notification time by stage. Measured on an iPhone 17 Pro with Presence holding: 1.3 s from hearing the change to the banner, 0.8 s of it naming the place.

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

`just check` and `just lint` run locally before a PR. github.com/harivansh-afk/TouchTips is the canonical repo and PRs merge there; git.harivan.sh keeps a read-only pull mirror. Builds ship through Xcode Cloud: every push to `main` archives and goes to TestFlight, with `scripts/ci_post_clone.sh` generating the project on the runner and stamping the build number. The workflow itself is configured in App Store Connect, not here.

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
