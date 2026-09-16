# Shortcuts automation onboarding options

Research date: 2026-09-16. This document separates what Apple documents from inference, for one question: can an iOS 26 app shorten or remove the manual setup of the personal automation "When Contacts is closed → run Check for new contacts"? Sources are Apple user guides (the iOS 26 revision of the Shortcuts User Guide where one exists), developer documentation, WWDC transcripts and Apple Developer Forums threads. Nothing here was tested on a phone as part of this research; the simulator tap count comes from the team's own observation and is labelled as such.

Two framing facts. Apple's current default Shortcuts guide already describes iOS 27, where automations became a property of a shortcut ("Tap Edit, then Automation") and run-without-asking moved under Privacy → "Allow Running When Locked". Every tap count below uses the iOS 26 revision of each page, since the target is iOS 26.5. [iOS 27 page](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios), [iOS 26 page](https://support.apple.com/guide/shortcuts/apdfbdbd7123/9.0/ios/26.0)

## Scope

In scope: personal automations and every documented way to create, share, import, pre-fill or deep-link one; App Shortcuts and the Gallery; alternative triggers that need fewer taps and no background location; iOS 26 and WWDC25 changes; the documented behavior of the "App is closed" trigger. Out of scope: repairing the location fallback (see [background discovery options](background-discovery-options.md)) and any server-side account integration.

Tap counting method: taps are counted from the numbered steps in Apple's guide for that feature. Swipes, press-and-hold and hardware presses are listed separately and not counted as taps. Where a guide step says "select a shortcut" or "choose an app" without listing the sub-taps, one tap is counted for the selection and one for any confirmation the step names. Counts derived this way are labelled "guide"; the team's simulator observation is labelled "measured".

## Findings summary

| Route | Taps to set up | Passive after setup? | Needs location? | Source |
| --- | --- | --- | --- | --- |
| Personal automation, App → Is Closed, by hand | 10 (guide), 11 (measured, iOS 26.5 simulator) | Yes, fires on every switch away from Contacts | No | [Create automation](https://support.apple.com/guide/shortcuts/apdfbdbd7123/9.0/ios/26.0), [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0) |
| Same, entered via `shortcuts://create-automation` from an in-app button | 1 in-app tap + 8 in Shortcuts (inference from the guide steps; the URL itself is undocumented) | Yes | No | Team observation; absent from [URL scheme guide](https://support.apple.com/guide/shortcuts/apda283236d7/ios) |
| Any API, file, link or share that installs an automation with a trigger | None exists | n/a | n/a | Inference from absence; see route 1 |
| App Shortcuts (Siri phrase, Spotlight) | 0 | No, one utterance or search per run | No | [WWDC25 244](https://developer.apple.com/videos/play/wwdc2025/244/), [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts) |
| Control Center control (app's own `ControlWidgetButton`) | 3 taps + 1 swipe; then 1 swipe + 1 tap per run | No | No | [Controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system), [Control Center guide](https://support.apple.com/guide/iphone/iph59095ec58/ios) |
| Action button → app control or App Shortcut | 3 taps + 1 swipe; then 1 press-and-hold per run | No | No | [Action button guide](https://support.apple.com/guide/iphone/iphe89d61d66/ios), [Shortcuts guide](https://support.apple.com/guide/shortcuts/apdfea15680b/ios) |
| Back Tap → shortcut | 6 taps; then a double tap on the case per run | No | No | [Back Tap guide](https://support.apple.com/guide/shortcuts/apd897693606/ios) |
| Home Screen interactive widget button | 5 taps + 1 press-and-hold; then 1 tap per run | No | No | [Widgets guide](https://support.apple.com/guide/iphone/iphb8f1bf206/ios), [Interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| Lock Screen widget button | 5 taps + press-and-hold; inactive until the device is unlocked | No | No | [Lock Screen guide](https://support.apple.com/guide/iphone/iph4d0e6c351/ios), [Interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| Focus filter (`SetFocusFilterIntent`) | 5 taps in Settings | Yes, but only on Focus transitions | No | [Focus filter sample](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter), [WWDC22 10121](https://developer.apple.com/videos/play/wwdc2022/10121/) |
| Personal automation, Time of Day / Charger / Wi-Fi / Focus trigger | 8 to 10 (guide) | Yes, on that event only | No | [Event triggers](https://support.apple.com/guide/shortcuts/apd932ff833f/9.0/ios/26.0), [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0) |
| `BGAppRefreshTask` | 0 | Yes, at system discretion | No | [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) |
| Background push | 0 on device, server required | Yes, not guaranteed, 2 to 3 per hour | No | [Background pushes](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) |
| `BGContinuedProcessingTask` (iOS 26) | User starts it in the foreground | No, visible progress and cancellable | No | [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) |
| NFC tag (Shortcuts trigger or background tag reading) | Similar to the App trigger, plus a physical tag | No, one tap of the tag per run | No | [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0), [Background tag reading](https://developer.apple.com/documentation/corenfc/adding-support-for-background-tag-reading) |
| App Clip, Live Activity, Watch complication, Home automation | Not applicable as a contact-discovery trigger | No | No | See route 3 |

## Route 1: personal automations

### What the App trigger does

Apple's iOS 26 guide documents the App trigger with three options: App ("Tap Choose, then select an app from the list"), Is Opened ("when you open or switch to the selected app") and Is Closed ("when you close or switch from the selected app"). Switching away is enough; the guide says nothing about whether swiping the app out of the switcher is treated differently from backgrounding it. [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0)

The App trigger is in the list of automations that "can be run automatically" (no confirmation). The guide's mechanism for this on iOS 26 is the automation's "Ask Before Running" toggle, confirmed with "Don't Ask"; it adds "You also may need to set individual actions to run automatically." The "Run Immediately / Run After Confirmation" and "Notify When Run" choices the team saw on the trigger-options screen are not in the guide text. [Enable or disable](https://support.apple.com/guide/shortcuts/apd602971e63/9.0/ios/26.0)

The automation runs the App Shortcut's intent. Shortcuts can run an intent without bringing the app forward when the intent is a background intent; Apple's example is creating a calendar event "in the background without opening the app". The intent's `supportedModes` decides this. [WWDC25 260](https://developer.apple.com/videos/play/wwdc2025/260/), [WWDC25 275](https://developer.apple.com/videos/play/wwdc2025/275/)

### Manual setup, counted from the guide

The iOS 26 "Create a new personal automation" page lists these steps: tap Automation (plus the "+" if an automation already exists); tap Create Personal Automation; choose a trigger; "Select the options for the trigger, then tap Next"; tap Add Action or pick from the offered "blank automation, a suggested automation, or use an existing shortcut"; tap Next; tap Done. [Create automation](https://support.apple.com/guide/shortcuts/apdfbdbd7123/9.0/ios/26.0)

Expanded for this trigger: Automation, +, Create Personal Automation, App, Choose, Contacts, confirm, Is Closed, Next, pick the TouchTips shortcut, Done. That is 10 to 11 taps depending on whether the "+" is needed and whether Is Closed is already selected. The measured count on the iOS 26.5 simulator is 11 (the team's flow adds the Run Immediately tap and skips "+"). The two numbers agree within the ambiguity of the guide.

### `shortcuts://` URL scheme

Apple documents exactly these URLs on iOS: `shortcuts://` (open the app), `shortcuts://create-shortcut` (open the editor on a new shortcut), `shortcuts://open-shortcut?name=` (open an existing shortcut), `shortcuts://run-shortcut?name=&input=&text=` (run one), `shortcuts://gallery` and `shortcuts://gallery/search?query=`, plus x-callback-url variants of run-shortcut. None opens the automation editor, none takes a trigger parameter. [Open and create](https://support.apple.com/guide/shortcuts/apda283236d7/ios), [Run from URL](https://support.apple.com/guide/shortcuts/apd624386f42/ios), [Gallery from URL](https://support.apple.com/guide/shortcuts/apd9c112ca23/ios), [x-callback-url](https://support.apple.com/guide/shortcuts/apdcd7f20a6f/ios)

`shortcuts://create-automation` and `shortcuts://automations`, which the team verified open the trigger picker and the Automation tab, appear in no Apple page found in this research. They are undocumented and could change or be removed. Inference: an in-app button that opens `shortcuts://create-automation` replaces the Automation-tab, "+" and Create Personal Automation taps with one in-app tap, leaving App, Choose, Contacts, confirm, Is Closed, Next, pick shortcut, Done: 8 taps inside Shortcuts. No documented URL pre-selects the trigger's app or option, so those 8 cannot be reduced by URL.

`shortcuts://import-shortcut?url=&name=&silent=` was documented in the Shortcuts 2.0 guide for iOS 12 ("A URL pointing to the .shortcut file you want to import"; "Before a shortcut imported from another app is run for the first time, you'll be asked for permission to run it"). It is absent from the iOS 26 URL scheme pages. A 2023 forum thread reports local `file://` URLs fail with "The file doesn't exist" and a remote URL crashed the app; it has no Apple reply. Either way, it imports a shortcut, not an automation. [Shortcuts 2.0 import page](https://support.apple.com/en-la/guide/shortcuts/apd77a47304b/2.0/ios/12.0), [Forum thread 726203](https://developer.apple.com/forums/thread/726203)

### Sharing, files and iCloud links

Shortcuts can be shared as an iCloud link or a `.shortcut` file. The recipient taps the link, sees a description and taps Get Shortcut or Add Shortcut; a file shared as "Anyone" is sent to Apple for validation, and shortcuts received privately from contacts require the Private Sharing setting. Import questions let a shared shortcut ask for personal values on first run. Every one of these pages describes shortcuts only. [Share shortcuts](https://support.apple.com/guide/shortcuts/apdf01f8c054/9.0/ios/26.0), [Privacy settings](https://support.apple.com/guide/shortcuts/apd961a4fc65/9.0/ios/26.0), [Import questions](https://support.apple.com/guide/shortcuts/apdf330fd3a0/ios)

Automations are the opposite: "Personal automation is specific to a device. The automation will be backed up to iCloud but will not sync to other devices." No guide page describes sharing, exporting or importing an automation. Conclusion from absence: there is no share or import path for a trigger, and the iCloud-sync exclusion means even Apple's own sync does not carry an enabled automation between the user's devices. [Intro to personal automation, iOS 26](https://support.apple.com/guide/shortcuts/apd690170742/9.0/ios/26.0)

### App Intents, Intents framework, NSUserActivity, Focus, Home

| Mechanism | What Apple documents | What it does not do |
| --- | --- | --- |
| `AppShortcutsProvider` / `AppShortcut` | Compiler-generated, "available as soon as someone installs your app", shown in Spotlight, Siri, the Shortcuts app, the Action button and Apple Pencil Pro with no registration. Phrases must include the app name. | Attach a trigger. Nothing in the type's documentation or WWDC25 sessions mentions automations. [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts), [AppShortcut](https://developer.apple.com/documentation/appintents/appshortcut), [WWDC24 10210](https://developer.apple.com/videos/play/wwdc2024/10210/) |
| `ShortcutsLink`, `SiriTipView` | A button "that brings users to the current app's App Shortcuts page in the Shortcuts app"; a view that "displays the phrase someone uses to invoke an App Shortcut". | Open the automation editor or create anything. [ShortcutsLink](https://developer.apple.com/documentation/appintents/shortcutslink), [SiriTipView](https://developer.apple.com/documentation/appintents/siritipview) |
| `INUIAddVoiceShortcutViewController`, `INShortcut` | "Guides the user through the steps for adding a shortcut to Siri", i.e. records a phrase for an intent. | Create an automation. [Add to Siri](https://developer.apple.com/documentation/intentsui/inuiaddvoiceshortcutviewcontroller) |
| `INVoiceShortcutCenter.setShortcutSuggestions` | Suggests shortcuts "for actions that the user hasn't performed"; "The user views the suggestions in the Gallery of the Shortcuts app." | Publish a triggered automation; it suggests shortcuts, and the suggestions still need user action. [INVoiceShortcutCenter](https://developer.apple.com/documentation/intents/invoiceshortcutcenter) |
| `NSUserActivity` donation | Handoff, Spotlight, Siri context. | Any scheduled or triggered execution. [NSUserActivity](https://developer.apple.com/documentation/foundation/nsuseractivity) |
| `SetFocusFilterIntent` | Runs when a Focus turns on or off, in the app or an App Intents extension if the app is not running; user adds it in Settings > Focus > (a Focus) > Add Filter > app > Add. | Fire on a contact save. See route 3 for its use as a passive wake. [Focus filter sample](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter), [WWDC22 10121](https://developer.apple.com/videos/play/wwdc2022/10121/) |
| HomeKit `HMEventTrigger` | Programmatically created triggers that "trigger the execution of a scene" (an action set of accessory changes). | Run a third-party app intent; a 2020 forum thread requesting exactly that has no reply. [HMEventTrigger](https://developer.apple.com/documentation/homekit/hmeventtrigger), [Forum thread 654844](https://developer.apple.com/forums/thread/654844) |

Apple staff replies found in the forums point the same direction. In November 2018 a DTS engineer answered a request to create shortcuts programmatically by linking the shortcut-suggestion documentation rather than any creation API. In November 2022 an Apple staff member wrote that "there's no mechanism for you to automatically launch an app when you unlock your device" and pointed the developer to personal automation in Shortcuts as the user-configured alternative. [Forum thread 110470](https://developer.apple.com/forums/thread/110470), [Forum thread 719125](https://developer.apple.com/forums/thread/719125)

Conclusion, stated as inference from absence: no public API, URL parameter, file format, iCloud link or share mechanism creates, pre-fills or installs a personal automation with a trigger on iOS 26. The floor for the App trigger is the trigger picker, reached either by the user's own navigation (10 to 11 taps) or by the undocumented `create-automation` URL (1 in-app tap plus 8).

## Route 2: App Shortcuts and the Gallery

App Shortcuts are installed with the app and need no setup ("App Shortcuts will show in the Shortcuts app without any user setup"). They are runnable, not triggered: the documented run surfaces are Siri phrases, Spotlight, the Shortcuts app, the Action button and Apple Pencil Pro. An App Shortcut does appear as a selectable action when the user builds an automation, which is why the manual flow needs only one tap to pick it. [WWDC25 244](https://developer.apple.com/videos/play/wwdc2025/244/), [Run app shortcuts](https://support.apple.com/guide/shortcuts/apd43295406d/ios)

The Gallery is described as "a curated collection" of shortcuts organised in category rows. No guide or developer page found describes a way for developers to publish to it, and the only app-originated content Apple documents there is `INVoiceShortcutCenter` suggestions. Gallery items are shortcuts; the Gallery pages do not mention automations. Inference from absence: developers cannot publish to the Gallery, and nothing in the Gallery installs a trigger. [Gallery](https://support.apple.com/guide/shortcuts/apdd018638ca/ios), [Gallery URL](https://support.apple.com/guide/shortcuts/apd9c112ca23/ios), [INVoiceShortcutCenter](https://developer.apple.com/documentation/intents/invoiceshortcutcenter)

## Route 3: alternative triggers

### Explicit, one-interaction triggers (no location)

| Trigger | Setup, from Apple's guide | Per run | Notes |
| --- | --- | --- | --- |
| Siri phrase / Spotlight | 0 taps | Speak the phrase, or search and tap Run | Phrases must include the app name. [WWDC25 244](https://developer.apple.com/videos/play/wwdc2025/244/), [Search screen](https://support.apple.com/guide/shortcuts/apd8a8ffb4ac/9.0/ios/26.0) |
| Control Center control | Open Control Center (swipe), tap "+", tap Add a Control, tap the TouchTips control: 3 taps | Swipe, 1 tap | The intent runs in the widget extension unless it opens the app; a control can require authentication when locked. [Control Center guide](https://support.apple.com/guide/iphone/iph59095ec58/ios), [Controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system), [Shortcuts in Control Center](https://support.apple.com/guide/shortcuts/apd06a9201d4/9.0/ios/26.0) |
| Action button | Settings, Action Button, swipe to Controls or Shortcut, tap the chooser, tap the control or App Shortcut: 3 taps | Press and hold | iPhone 15 Pro or later. App Shortcuts "automatically worked with the Action button". [Action button guide](https://support.apple.com/guide/iphone/iphe89d61d66/ios), [WWDC24 10210](https://developer.apple.com/videos/play/wwdc2024/10210/) |
| Back Tap | Settings > Accessibility > Touch > Back Tap > Double Tap > shortcut > Back Tap: 6 taps | Double-tap the back of the phone | [Back Tap guide](https://support.apple.com/guide/shortcuts/apd897693606/ios) |
| Home Screen widget button | Press and hold, tap Edit, Add Widget, the widget, Add Widget, Done: 5 taps | 1 tap | `Button(intent:)` runs `perform()` in the extension process. [Widgets guide](https://support.apple.com/guide/iphone/iphb8f1bf206/ios), [Interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| Lock Screen widget button | Press and hold the Lock Screen, Customize, the Lock Screen, Add Widgets, the widget, Done: 5 taps | 1 tap after unlocking | "On a locked device, buttons and toggles are inactive." [Lock Screen guide](https://support.apple.com/guide/iphone/iph4d0e6c351/ios), [Interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| NFC | Shortcuts NFC trigger needs the same automation flow plus a tag scan; background tag reading needs a universal link, shows a notification the user taps, and "doesn't support custom URL schemes" | Tap the tag, then possibly the notification | [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0), [Background tag reading](https://developer.apple.com/documentation/corenfc/adding-support-for-background-tag-reading) |

All of these are supported building blocks for a "check now" action. None observes a contact save; each needs one deliberate user action per check.

### Passive triggers without location

| Trigger | Setup | When it fires | Limits |
| --- | --- | --- | --- |
| Focus filter | Settings > Focus > (a Focus) > Add Filter > TouchTips > Add: 5 taps, once per Focus | When that Focus turns on or off; an App Intents extension is spun up if the app is not running | Fires only on Focus transitions (for many users, Sleep on/off gives two per day). Apple frames the intent as adapting behavior to Focus; using `perform()` to run a Contacts-history fetch is not documented as a purpose, and is an inference that the docs permit it. [Focus filter sample](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter), [WWDC22 10121](https://developer.apple.com/videos/play/wwdc2022/10121/) |
| Personal automation with Time of Day, Charger, Wi-Fi, Bluetooth, Alarm, Sleep or Focus trigger | 8 to 10 taps by the same guide steps as the App trigger; the trigger screens have fewer choices than App (no app picker) | On the event; all are in the run-automatically list | Same creation floor as the App trigger, so no tap saving; a 2020 to 2024 forum thread reports Time of Day automations not firing on locked idle devices, with no Apple reply. [Event triggers](https://support.apple.com/guide/shortcuts/apd932ff833f/9.0/ios/26.0), [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0), [Forum thread 665845](https://developer.apple.com/forums/thread/665845) |
| `BGAppRefreshTask` | 0 taps; `fetch` background mode | At system discretion, for "small bits of information" | Already declared by the app; no timing contract. [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) |
| Background push | 0 taps; needs a server | Wakes the app for 30 seconds; delivery "not guaranteed", held and coalesced, "don't try to send more than two or three per hour" | A server still has no way to know a contact was saved locally. [Background pushes](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) |
| `BGContinuedProcessingTask` (iOS 26) | User starts it in the foreground | Continues in the background with a Live Activity showing progress and a cancel control; can be terminated under resource pressure | Not passive and not invisible. [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) |

### Not applicable

App Clips launch only from an invocation such as scanning a code, tapping a link or a Smart App Banner, and the full app replaces the clip once installed. Live Activities are started by the app or by a push and their buttons run intents on tap. Watch complications and Lock Screen accessory widgets are glanceable views whose taps open the app. HomeKit automations execute scenes, not app intents. None is a background trigger for Contacts changes. [App Clip invocations](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip), [ActivityKit](https://developer.apple.com/documentation/activitykit), [Accessory widgets](https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications), [HMEventTrigger](https://developer.apple.com/documentation/homekit/hmeventtrigger)

## Route 4: iOS 26 and WWDC25 changes

Apple's "What's new in Shortcuts 26" article lists new intelligent actions ("Use Model", Writing Tools, Image Playground), around 25 new app actions, editor improvements, and, on macOS only, personal automations (including an App "opened or closed" trigger), Spotlight execution and Control Center controls. The iOS automation trigger list is unchanged; there is no Contacts trigger, and "Find Contacts" gained only a relationship filter. [What's new in Shortcuts 26](https://support.apple.com/en-us/125148), [Use Apple Intelligence in Shortcuts](https://support.apple.com/guide/iphone/iph78c41eaf8/26/ios/26)

The three App Intents sessions cover interactive snippets, `supportedModes` for background and foreground execution, Spotlight on Mac, entities for the Use Model action, and the Mac automations. "As long as your intent is available on macOS, they will also be available to use in Shortcuts to run as a part of Automations on Mac" is the only automation statement, and it is about the action side, not creating triggers. No session introduces an API for automations, and none mentions Contacts triggers. [WWDC25 244](https://developer.apple.com/videos/play/wwdc2025/244/), [WWDC25 260](https://developer.apple.com/videos/play/wwdc2025/260/), [WWDC25 275](https://developer.apple.com/videos/play/wwdc2025/275/)

The Contacts and ContactProvider documentation shows no iOS 26 additions relevant to observing saves; ContactProvider's direction remains app → system, as recorded in the earlier research. [Contacts](https://developer.apple.com/documentation/contacts), [background discovery options](background-discovery-options.md)

The "What's new in iOS 26" user guide page does not mention Shortcuts, automations or Contacts. [What's new in iOS 26](https://support.apple.com/guide/iphone/iphfed2c4091/26/ios/26)

## Route 5: documented behavior of "App is closed"

Documented: the trigger fires "when you close or switch from the selected app"; App is in the list of automations that can run without asking; turning off Ask Before Running means "The automation will not notify you when it's triggered"; individual actions may also need to be set to run automatically. [Setting triggers](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26.0), [Enable or disable](https://support.apple.com/guide/shortcuts/apd602971e63/9.0/ios/26.0)

Not documented: any difference between backgrounding Contacts and swiping it away; whether the trigger fires while the device is locked; a latency figure; the "Run Immediately" and "Notify When Run" controls seen during creation. The iOS 27 guide adds "Allow Running When Locked" under the shortcut's Privacy settings, which suggests locked-state execution is a distinct permission there; the iOS 26 guide has no equivalent statement. [iOS 27 automations page](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios)

## Bottom line

Minimum-tap passive option that actually covers the use case: the App → Is Closed personal automation, with the user reaching the trigger picker through an in-app button that opens the undocumented `shortcuts://create-automation` URL. Cost is 1 in-app tap plus 8 in Shortcuts (inference), against 10 to 11 by hand. Nothing documented pre-fills the app, the option or the action, and nothing installs or shares an automation. The URL is unsupported and should be guarded: if it fails to open, fall back to `shortcuts://` plus written steps. This route has no location requirement.

Minimum-tap passive option overall, ignoring coverage: a Focus filter (5 taps in Settings) gives a documented background wake on every Focus transition with no automation at all, and `BGAppRefreshTask` and background pushes give zero-tap wakes with no timing contract. These are supplementary wake sources for the existing coalesced Contacts-history fetch, not a replacement for the App trigger, because they fire on a schedule unrelated to contact saves.

Minimum-tap non-passive option: an App Shortcut with a Siri phrase costs zero setup taps. For a tap-driven check, the app's own Control Center control (3 taps plus a swipe to set up, swipe plus one tap per run) and the Action button on iPhone 15 Pro or later (3 taps plus a swipe to set up, one press-and-hold per run) are the cheapest documented surfaces.

## Unverified

- The `shortcuts://create-automation` and `shortcuts://automations` URLs: not in any Apple page found. Their behavior is the team's simulator observation only, and the 8-tap count after the URL is inferred from the guide steps, not measured.
- Whether "Is Closed" fires when Contacts is swiped out of the app switcher, when the device locks with Contacts frontmost, or while the device is locked; and the fire-to-run latency.
- Whether "Run Immediately" chosen during creation is identical to turning off "Ask Before Running" afterwards; the guide documents only the latter.
- Whether Shortcuts offers the TouchTips App Shortcut among the "suggested automation" options after the trigger step, which would make the action pick a single tap or none.
- Whether a Focus filter extension gets enough time and Contacts access to complete a history fetch, and whether Apple review accepts that use of `SetFocusFilterIntent`.
- Whether `shortcuts://import-shortcut` still functions on iOS 26 at all; its only current documentation is the iOS 12 guide and a 2023 forum report of failures with no Apple reply.
- Whether iOS 27's model, where automations belong to a shortcut, lets a shared shortcut carry its trigger. The iOS 27 pages read do not say either way, and iOS 27 is outside this document's target.
- Whether home automations in Shortcuts can run third-party app intents on the home hub; no Apple page examined states this, and the HomeKit API only executes scenes.
