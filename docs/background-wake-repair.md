# Repairing continuous background location for contact discovery

Research date: 2026-09-09. This addendum identifies a concrete configuration hypothesis after the build 72 phone failure. The proposed configuration has not yet been validated on the phone; it is not a claim that notification reliability or battery use is already fixed.

## The specific guidance missed previously

Apple's general recommendation to use coarse accuracy with automatic pausing disabled was incomplete guidance for this app's configuration. An Apple Engineer documents a deliberate change in iOS 16.4 and later: combining `startUpdatingLocation()` and `startMonitoringSignificantLocationChanges()` with coarse settings can result in background suspension. For continuous delivery, the answer gives a high-accuracy configuration, then a separate alternative:

> Alternatively you can turn on the location indicator which will avoid the issue.

That alternative is `showsBackgroundLocationIndicator = true`. The answer does not impose the high-accuracy branch's threshold on the indicator alternative. The other branch requires background updates enabled, no distance filtering, and `kCLLocationAccuracyHundredMeters` or better; numeric accuracy must be below 1000 m. The answer classifies kilometer-and-coarser requirements as low accuracy. TouchTips currently requests `kCLLocationAccuracyThreeKilometers`, disables the indicator, and starts both services. [Apple Engineer's configuration guidance](https://developer.apple.com/forums/thread/726945)

The indicator switch applies specifically to Always-authorized apps. When In Use apps already show it for continuous background location. Thus having Always permission does not make this switch irrelevant. [Indicator documentation](https://developer.apple.com/documentation/corelocation/cllocationmanager/showsbackgroundlocationindicator), [Apple QA1965](https://developer.apple.com/library/archive/qa/qa1965/)

The build 72 trace shows both services configured, successful Always authorization and the repaired fence, followed by suspension and no delivered app events during an external save. This matches the configuration hypothesis; it does not establish that the indicator alone will cure it. Private evidence is in the main checkout's ignored `build/phone-audit-20260909-regression/findings.md`.

## First candidate and startup lifecycle

Keep the existing coarse accuracy, no distance filter, `.other` activity and disabled automatic pausing; set the background indicator to true before starting standard updates. This changes the documented visibility condition without immediately increasing requested accuracy. It may still increase energy use by allowing longer execution; there is no measured battery result yet.

Apple DTS reaffirmed the iOS 16.4 behavior in March 2025 and separately states that standard updates must start in the foreground to continue in the background. The stated exception is activation caused by a significant-location-change callback. A visit or arbitrary background refresh does not establish the same eligibility. [Apple DTS startup guidance](https://developer.apple.com/forums/thread/776698)

Recommended lifecycle:

1. Initialize the delegate, Contacts observer, low-power monitoring and existing Always monitor session promptly on launch. Preserve their background-relaunch recovery paths.
2. When the app becomes active and its already-enabled presence policy calls for continuous location, apply the configuration and start standard updates from that foreground context. No separate recurring Start control is required by this API guidance.
3. Retain that session while the enabled feature needs it when the user changes apps. Stop when the feature is disabled or authorization is lost. Do not stop merely because the app enters the background.
4. If startup occurred in the background, do not treat a successful method call or local `presenceActive` Boolean as proof of an effective continuous session. Reestablish it on the next eligible foreground transition. Handle a genuine significant-change activation separately where the source is known; do not infer it solely from a generic location-launch flag.
5. Scan promptly on a resumed location opportunity instead of discarding the opportunity under the existing five-minute movement throttle. Coalesce repeated callbacks and use the Contacts history cursor so this does not become an expensive scan for every fix.

Items 1–5 are implementation recommendations applying Apple's lifecycle rules to the inspected TouchTips code. They still need tests. A persisted location-capture preference and granted permission can describe an ongoing feature; the recommendation is not an interpretation of `BGContinuedProcessingTask`'s different user-action requirements.

## Why not replace everything with liveUpdates first

`CLBackgroundActivitySession` supports an ongoing location feature without a recurring manual button. The iOS 26.5 SDK header says a new session can become active while foregrounded and in direct use; it can continue after the process stops and be resumed immediately on the next launch, including background launch. An abandoned session must qualify again. This supports automatic foreground restoration of a previously enabled feature, with a visible indicator. [Background location setup](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [WWDC23 session lifecycle](https://developer.apple.com/videos/play/wwdc2023/10180/)

However, `CLLocationUpdate.liveUpdates()` automatically pauses when stationary and can suspend the app while there are no updates. It then resumes when location information returns. A migration is useful for diagnostics and modern lifecycle management, but it changes the very stationary behavior being tested and is not a documented stationary keep-alive replacement. [WWDC23 automatic pause/resume](https://developer.apple.com/videos/play/wwdc2023/10180/), [WWDC24 lifecycle](https://developer.apple.com/videos/play/wwdc2024/10212/)

## Controlled phone experiments

| Candidate | Change | What the result isolates |
| --- | --- | --- |
| A | Foreground-started 3 km standard updates, indicator enabled | Whether the documented visibility alternative prevents the reproduced suspension without higher requested accuracy. |
| B, only if A fails | Foreground-started 100 m standard updates, no distance filter; keep the indicator enabled | Whether a stronger location request changes current-device delivery. This increases requested accuracy and requires battery measurement. |
| C, separate experiment | Modern retained activity/service sessions and live updates | Whether modern lifecycle recovery improves real-world gaps; separately measure stationary automatic pausing. |

For each candidate, launch from the Home Screen without a debugger, switch to Instagram, remain stationary past the previous suspension window, and then save a new contact through Apple Contacts without reopening TouchTips. Repeat after a longer idle, with the device locked before the save, while moving, and after process termination/relaunch. Record source save time, RunningBoard execution state, location callback time, Contacts observation time, notification submission time and visible alert time. A USB cable alone is not the problematic debugger attachment.

Keep the wake/lifecycle repairs constant when comparing A with B. Comparing the complete repair against build 72 evaluates the combined change; it does not isolate the indicator's effect from the scheduling and manager-lifecycle changes. The hypothesis is supported only if the app stays eligible and detects the save before foregrounding. A single successful event establishes that path once; repeated stationary/locked/moving trials and a longer battery comparison are required before claiming broad reliability. Higher accuracy can use more hardware and more time, and more sustained process activity also costs energy. [Accuracy and energy guidance](https://developer.apple.com/documentation/corelocation/cllocationmanager/desiredaccuracy)
