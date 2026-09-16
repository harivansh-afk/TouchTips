# Shortcuts automation onboarding precedents

Research date: 2026-09-16. Companion to [shortcuts-onboarding-research.md](shortcuts-onboarding-research.md). Question: which shipping iOS apps make the user build a Shortcuts personal automation by hand for a core feature, how they onboard that setup, what step counts they document, and whether they later moved to a first-party API. Sources are the apps' own help centres, blogs and App Store listings, Apple guides and WWDC transcripts, plus two named secondary write-ups where no primary page exists. Nothing was tested on a device. Step counts are the numbered steps in each app's own guide, labelled "guide"; where a guide folds several taps into one step, the count is steps, not taps.

Two framing facts. First, every app found that depends on an automation uses the App → Is Opened trigger, so their guides are the closest published analogue to the App → Is Closed flow in the companion document. Second, iOS 27 changed the ground: automations became actions inside a shortcut and shortcuts that contain them can be shared, arriving disabled until the recipient flips a toggle. one sec shipped a one-tap setup on that basis on 2026-09-14, two days before this research. [MacStories iOS 27 review](https://www.macstories.net/stories/ios-and-ipados-27-review/13/), [one sec 6.0](https://one-sec.app/blog/one-sec-6.0/)

## Summary

| App | What the automation does | Required? | Onboarding pattern | Documented steps (guide) | Later moved to |
| --- | --- | --- | --- | --- | --- |
| one sec (24K ratings, 4.8) | App → Is Opened runs "Activate one sec", showing a breathing pause before the social app | Required for the core intervention, 2020 to 2026 | In-app quiz first, then per-iOS-version written tutorial with screenshots and video; one automation per app | 8 (iOS 16 guide), 7 (iOS 17 to 26 guide), "10-step" in the developer's own description | Screen Time API for blocks (by 2024); Focus filter (2022); iOS 27 shared automation, "confirm and that's it" (Sept 2026) |
| Jomo (2.4K ratings, 4.8) | App → Is Opened runs "Count App Open" for Open Limits; other triggers start or stop block sessions | Optional; Open Limits is "Legacy" and "no longer supported" | Help-centre articles with screenshots; in-app "Automation set up?" checkpoint; rule name must match exactly | 7 in Jomo + 10 in Shortcuts (Open Limits); 10 to 12 per trigger example | Core blocking is Screen Time API; Focus filter route documented (5 + 5 steps) |
| Opal (88K ratings, 4.7, Editors' Choice) | Do Not Disturb, Arrive or App → Is Opened starts a block session | Optional | Help-centre article, screenshots, iCloud links for the trigger-less shortcuts | 9 (DND), 10 (Arrive), 9 (App opened) | Core is Screen Time API; Focus mode integration |
| ScreenZen (50K ratings, 4.9) | App → Is Opened redirects to ScreenZen (secondary sources only) | Unclear; Screen Time permission is the first onboarding step | "How-to Setup" button in the More tab that pops instructions (secondary source) | Not published | App Store listing describes Screen Time API use |
| Streaks | App → Is Opened marks a habit complete | Optional | No first-party guide found; a 2019 Sweet Setup walkthrough | 7 (third-party guide) | n/a |
| Timery (Toggl) | App → Is Opened starts a time entry | Optional | No first-party guide found; a 2021 Sweet Setup walkthrough | 7 (third-party guide) | Focus filters and Control Center controls listed on the product site |
| Clearspace, Refocus, Brick | None found | No | Screen Time API (plus NFC hardware for Brick) | n/a | n/a |

## one sec

Documented. one sec launched in September 2020 as a Shortcuts automation app: "one sec uses Shortcuts Automation to toggle a deep breath animation whenever you open one of the configured apps"; "The setup is easy: configure the one sec Shortcut to be triggered when opening an app – within the Shortcuts app", with "video instructions" inside the app. The founder's launch post reports a 40% screen-time reduction after two weeks of his own use. [riedel.wtf one sec](https://riedel.wtf/one-sec/), [Riedel on X, Oct 2020](https://x.com/frederikRiedel/status/1315324134327549952), [How one sec works](https://one-sec.app/blog/how-one-sec-works/)

The setup guides, by iOS version:

- iOS 16 and earlier, 8 steps: Automation tab; create personal automation; App; choose one app ("Only select one app here. A separate automation is required for each app") and Next; Add Action; search "one sec" and pick "Activate one sec (when app opens)"; tap "App (must be selected)" to re-select the app ("The Automation won't run without this") and Done; toggle off Ask Before Running and Done, "very important". [Before iOS 17](https://tutorials.one-sec.app/en/articles/3795458)
- iOS 17 to 26, 7 steps: Automation tab; create personal automation; App; choose the app; Create New Shortcut; search "one sec" and pick the action; re-select the app and Done. Users on older iOS are sent to the previous tutorial. [Current setup](https://tutorials.one-sec.app/en/articles/3034626)
- An earlier revision of the same page had 9 steps, the ninth an optional iOS 15.4+ notification switch-off, because "Automations always trigger annoying notifications that pile up in your notification center". [Earlier setup page](https://one-sec.riedel.wtf/setup), [Disable notifications](https://one-sec.app/blog/disable-shortcuts-automation-notifications/)
- The company describes the same flow as "a technical 10-step process" and "an extensive 10-step process". The three counts differ by how sub-taps are grouped, not by the flow. [App Store](https://apps.apple.com/us/app/one-sec-screen-time-focus/id1532875441), [one sec 6.0](https://one-sec.app/blog/one-sec-6.0/)

Onboarding shape: a psychological quiz and a personalised intervention recommendation come first; Screen Time permission is requested next; the Shortcuts setup comes after that, with video tutorials, and "involves switching between one sec and the Shortcuts app" (secondary source, a UI teardown). Per-iOS-version setup videos exist on YouTube ("New on iOS 17+", "New on iOS 26+"). [screensdesign teardown](https://screensdesign.com/showcase/one-sec-screen-time-focus), [iOS 17+ video](https://www.youtube.com/watch?v=UVKVTcYWTdQ), [iOS 26+ video](https://www.youtube.com/shorts/w39EqhnYcvM)

First-party APIs adopted alongside the automation, not instead of it:

- Focus filter, June 2022: "iOS Settings → Focus → select a Focus (e.g. Work) and scroll all the way down to Focus Filters. Tap on Add Filter → one sec". [Focus filters](https://one-sec.app/blog/focus-filters-ios-16/)
- Screen Time API (DeviceActivity, ManagedSettings, FamilyControls) for blocks and "Re-Interventions". The founder's September 2024 post lists five filed bugs, including that a shield cannot return the user to the parent app, so the workaround is a local notification the user must tap, and the app never learns which apps were picked. Their tutorial adds a 50-token shield cap and a picker crash fixed in iOS 26. iOS 26.4 let users passcode-lock the permission. [Screen Time API issues, riedel.wtf](https://riedel.wtf/state-of-the-screen-time-api-2024/), [Screen Time API issues, tutorial](https://tutorials.one-sec.app/en/articles/3036354), [iOS 26.4 lock](https://one-sec.app/blog/lock-screen-time-permission/)

Version 6.0, 2026-09-14: "you no longer have to set up Shortcuts automations manually! Simply tap on 'Add Intervention' to automatically import the automation. This makes one sec's setup a one-step process, instead of a technical 10-step process." The blog post: "with iOS 27 ... We are sharing automations directly with the user: Manual setup is no longer necessary!"; "Now, setup takes literally one sec: confirm the automation for an intervention. That's it."; and "automation setup was always a bottleneck in recruiting participants" for their studies. The App Store note calls it "by far the biggest complaint we've heard over the years". [App Store version history](https://apps.apple.com/us/app/one-sec-screen-time-focus/id1532875441?see-all=version-history), [one sec 6.0](https://one-sec.app/blog/one-sec-6.0/)

Inference. The 6.0 mechanism is not named, but it matches the iOS 27 change where a shared shortcut carries its automation and the recipient enables it with one toggle; the "confirm" in one sec's wording is most likely that toggle plus the Add Shortcut sheet. Also inference: one sec kept the automation as the intervention trigger for six years despite using the Screen Time API for blocking, which is consistent with the API bug they filed (no way to bring the user back to the parent app from a shield).

## Jomo

Documented. Core blocking is first-party: "To access your screen time and block apps, Jomo uses the secure Screen Time API provided by Apple." Shortcuts automations are a separate, optional layer with its own help category. [App Store](https://apps.apple.com/us/app/jomo-screen-time-blocker/id1609960918), [Help category](https://help.jomo.so/en/category/shortcuts-focus-modes-widgets-1y5ioz5/)

Open Limits, the one feature that needs an App → Is Opened automation, is marked "Legacy", "available in Advanced mode" and "no longer supported by Jomo". The guide (updated 2026-06-15) lists 7 steps in Jomo, ending with a "Automation set up?" prompt the user confirms, then 10 in Shortcuts: open Shortcuts; Automation → New Automation; App; choose the same apps as in Jomo; Is Opened and Run Immediately; Next; new automation; search "Count App Open"; type the rule name; confirm. "The name of your rule in Shortcuts and in Jomo must be exactly the same, including spaces, capitalization, and punctuation." Three screenshots. [Count app opens](https://help.jomo.so/en/article/setup-an-automation-to-count-app-opens-117s5wo/)

A second guide (2025-10-01) uses the same trigger to "redirect from the blocked app to Jomo" for users who want blocking without Screen Time, 10 steps. [Block without Screen Time](https://help.jomo.so/en/article/how-to-block-apps-without-apples-screen-time-lv0ux6/)

Seven further automation recipes (Battery Level, Wi-Fi, Sleep, NFC, Transaction, Time of Day, CarPlay) are 10 to 12 steps each, all require Run Immediately, all recommend turning off Show When Run, each has one screenshot, and the text notes that iOS 17 and 18 say "New Blank Automation" where iOS 26 says "Create New Shortcut". [Automate Jomo](https://help.jomo.so/en/article/how-to-automate-jomo-with-shortcuts-and-siri-17p3ehp/)

The Focus route is a Focus filter, not an automation: 5 steps in Jomo to make a template, then Settings → Focus → the Focus → Add filter → Jomo → template, 5 steps. [Focus Modes](https://help.jomo.so/en/article/how-to-block-apps-on-my-iphone-using-focus-modes-1g9xjgv/)

## Opal

Documented. "We use Apple's Screen Time API in order to monitor and block apps you use"; "Connect iPhone shortcut automations to start/stop Focus Sessions based on app opens, time, location and more!" Apple Editors' Choice. [App Store](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230), [Opal vs Screen Time](https://opalapp.com/help/how-is-opal-different-from-screen-time-settings-on-ios)

The help article lists three trigger recipes with screenshots: Do Not Disturb (9 steps), Arrive (10 steps, with "Opal does not have access to any location data. Shortcuts simply recognizes your location."), and App → Is Opened (9 steps: Shortcuts; Automation; "+"; the app; Choose and confirm; Is Opened and Run Immediately; Next and New Blank Automation; search Start Session and pick a Block List; Done). Two trigger-less recipes are delivered as pre-built shortcuts via iCloud link. Troubleshooting is "update your OS if the action descriptions don't match". No in-app button opening Shortcuts is mentioned. [5 ways to use Opal with Shortcuts](https://opalapp.com/help/5-ways-to-use-opal-with-shortcuts)

The Shortcuts actions themselves were expanded in v3.26 (2023-06-05) after community requests for error handling and session-state checks. [Community thread](https://community.opalapp.com/t/advanced-shortcuts-support-released-on-v-3-26/393/1)

## ScreenZen

Documented, primary: the App Store listing (4.9, 50K ratings) describes Screen Time API use and lists "improved onboarding" in version notes; the product site says nothing about mechanism. [App Store](https://apps.apple.com/us/app/screenzen-screen-time-control/id1541027222), [screenzen.co](https://screenzen.co/)

Secondary only: a July 2025 review says the More tab has "a place to actually use the Shortcuts app on Apple to help block apps. You simply need to follow the instructions that will pop up when you press the How-to Setup button", after a first-run Screen Time permission page; an August 2026 blog says the app needs "Screen Time and Shortcuts permissions on iPhone" and "It's worth taking two minutes to set these up correctly". No ScreenZen help page for this was found. [Diary of the Mind review](https://diaryofthemind.com/screenzen-review-everything-you-need-to-know/), [Nibble blog](https://nibble-app.com/blog/screenzen)

## Streaks and Timery

Both expose actions that users wire to an App → Is Opened automation, and neither publishes its own automation guide. The Sweet Setup walkthroughs are 7 steps each and both end with "toggle off Ask Before Running" as the step that makes it an automation rather than a prompt. Timery's site lists Shortcuts actions, Focus filters and Control Center controls as first-party surfaces. [Streaks walkthrough, 2019](https://thesweetsetup.com/automating-habit-tracking-streaks-shortcuts/), [Timery walkthrough, 2021](https://thesweetsetup.com/triggers-app-open-automations/), [timeryapp.com](https://timeryapp.com/)

## Apps checked with no automation dependency

Clearspace's listing mentions neither Shortcuts nor a setup guide. Refocus describes Screen Time-style blocking, strict modes and NFC; its only Shortcuts mention is a grayscale-at-bedtime tip. Brick is Screen Time API plus an NFC tag; setup is NFC on, then an account. None documents an automation. [Clearspace](https://apps.apple.com/us/app/clearspace-reduce-screen-time/id1572515807), [Refocus](https://apps.apple.com/us/app/refocus-screen-time-blocker/id1645639057), [Brick FAQ](https://getbrick.com/pages/faq), [Brick support](https://support.getbrick.com/en/categories/1286465)

No sleep or charging app was found whose own documentation asks for a Charger, Sleep or Time of Day automation; those recipes appear only in Apple's guide, community threads and press. [Event triggers](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios), [Apple Community thread](https://discussions.apple.com/thread/256275734)

## What the first-party routes cost

| Route | User-facing cost, from Apple's own description | Source |
| --- | --- | --- |
| Screen Time API authorization (individual, iOS 16+) | One system alert, tap Allow, then Face ID, Touch ID or passcode; later calls "silently succeed"; two switches in Settings revoke it | [WWDC22 110336](https://developer.apple.com/videos/play/wwdc2022/110336/) |
| FamilyActivityPicker | The user picks apps, sites or categories in a system picker; the app receives opaque tokens and "no one outside of a single Family Sharing group will know what apps and websites are being used" | [WWDC21 10123](https://developer.apple.com/videos/play/wwdc2021/10123/) |
| Focus filter | Settings → Focus → a Focus → Add Filter → app → Add; fires only on Focus transitions | [one sec Focus filters](https://one-sec.app/blog/focus-filters-ios-16/), [Jomo Focus Modes](https://help.jomo.so/en/article/how-to-block-apps-on-my-iphone-using-focus-modes-1g9xjgv/) |
| iOS 27 shared shortcut with automation | Recipient adds the shortcut; automations "will be disabled by default (and visibly grayed out)" and need their main toggle flipped; Apple's guide adds they sync to other devices disabled | [MacStories](https://www.macstories.net/stories/ios-and-ipados-27-review/13/), [Apple intro, iOS 27](https://support.apple.com/guide/shortcuts/apd690170742/ios) |

Inference on tap counts: the Screen Time authorization is roughly two taps plus a biometric, and the picker is one tap per app plus Done. That is the floor one sec, Jomo and Opal pay for blocking, against 7 to 12 guide steps per app for the automation. Neither Apple's WWDC26 Shortcuts session nor the iOS 27 share guide mentions app-originated automations; the session covers three new triggers (Screenshot, Keyboard, Notification) and automations moving into the editor. [WWDC26 310](https://developer.apple.com/videos/play/wwdc2026/310/), [Share shortcuts, iOS 27](https://support.apple.com/guide/shortcuts/apdf01f8c054/ios)

## Patterns

1. Ship the value first, the automation second. one sec runs a quiz and a recommendation, then Screen Time permission, then the Shortcuts tutorial. ScreenZen puts Screen Time permission on first run and the Shortcuts setup behind a button in a secondary tab. [screensdesign](https://screensdesign.com/showcase/one-sec-screen-time-focus), [Diary of the Mind](https://diaryofthemind.com/screenzen-review-everything-you-need-to-know/)
2. One numbered step per screen, one screenshot per step, and a separate tutorial per iOS version. one sec keeps three versions of the same page; Jomo inlines the iOS 17/18 vs 26 wording; Opal says update iOS if labels differ. [one sec](https://tutorials.one-sec.app/en/articles/3034626), [Jomo](https://help.jomo.so/en/article/how-to-automate-jomo-with-shortcuts-and-siri-17p3ehp/), [Opal](https://opalapp.com/help/5-ways-to-use-opal-with-shortcuts)
3. A video of the whole flow, re-recorded per iOS version. [one sec iOS 17+](https://www.youtube.com/watch?v=UVKVTcYWTdQ), [one sec iOS 26+](https://www.youtube.com/shorts/w39EqhnYcvM)
4. Call out the silent-failure steps with warning glyphs: Ask Before Running off (or Run Immediately), the action's app parameter re-selected, and an exact name match between app and shortcut. Every guide read does at least the first. [one sec](https://tutorials.one-sec.app/en/articles/3795458), [Jomo](https://help.jomo.so/en/article/setup-an-automation-to-count-app-opens-117s5wo/)
5. Tell the user to switch off Notify When Run / Show When Run, or the automation spams the notification centre. [one sec](https://one-sec.app/blog/disable-shortcuts-automation-notifications/), [Jomo](https://help.jomo.so/en/article/how-to-automate-jomo-with-shortcuts-and-siri-17p3ehp/)
6. One automation per target app; the guide says so and the user repeats it. [one sec](https://tutorials.one-sec.app/en/articles/3795458)
7. An in-app self-report checkpoint, not detection. Jomo asks "Automation set up?" and the user confirms; no app found claims to detect that the automation exists or ran. [Jomo](https://help.jomo.so/en/article/setup-an-automation-to-count-app-opens-117s5wo/)
8. Where no trigger is needed, hand out a pre-built shortcut via iCloud link instead of steps. [Opal](https://opalapp.com/help/5-ways-to-use-opal-with-shortcuts)
9. Offer a first-party fallback with fewer taps: Focus filters for schedule-shaped use, Screen Time API for enforcement. All three blockers document both. [one sec](https://one-sec.app/blog/focus-filters-ios-16/), [Jomo](https://help.jomo.so/en/article/how-to-block-apps-on-my-iphone-using-focus-modes-1g9xjgv/), [Opal](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230)
10. Demote rather than remove. Jomo keeps the automation-based feature as "Legacy", "Advanced mode", "no longer supported". [Jomo](https://help.jomo.so/en/article/setup-an-automation-to-count-app-opens-117s5wo/)
11. When the OS allows it, replace the tutorial with a share. one sec 6.0 on iOS 27: tap Add Intervention, confirm the imported automation. [one sec 6.0](https://one-sec.app/blog/one-sec-6.0/)

## Unverified

- The exact mechanism and tap count behind one sec 6.0's "Add Intervention" on iOS 27: whether it is a shared shortcut carrying the automation, whether Shortcuts opens a sheet, and whether the user still flips the disabled-by-default toggle MacStories describes. Neither the App Store note nor the blog names an API.
- Whether the iOS 27 sharing path is available to iOS 26 users at all; every source read ties it to iOS 27. Out of scope for a 26.5 target.
- ScreenZen's use of an App → Is Opened automation and its "How-to Setup" button: two secondary sources, no ScreenZen help page, and the App Store listing does not mention Shortcuts.
- Clearspace's mechanism: a search snippet attributes Screen Time API use to a Show HN page that was not fetched.
- Any user-review, churn or conversion figure tied to automation friction. The only first-party statements are one sec's "biggest complaint we've heard over the years" and "bottleneck in recruiting participants", and a UI teardown's opinion that app-switching "could cause some users to drop off". No number was found.
- Whether any app detects that its automation exists or has fired; none documents it, and the absence is inference.
- The YouTube setup videos' channel ownership and upload dates; the page fetch returned titles only.
- Timery's and Streaks' own guidance, if any; only third-party walkthroughs were found.
