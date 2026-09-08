# Apple notification and capture constraints

Research date: September 8, 2026. Sources are Apple documentation, Apple DTS answers, the installed Apple `devicectl` help, and upstream libimobiledevice documentation. Code observations describe the architecture at the start of this audit; they are not claims that a later implementation still has those defects.

## What consistency can mean

TouchTips can make discovery and notification submission recoverable whenever iOS gives the process execution time. It cannot promise an immediate alert for every contact saved while suspended or terminated. Apple documents `CNContactStoreDidChange` as a store-change notification, with no launch entitlement or background wake guarantee. Apple DTS states that a suspended process executes no code and that no general API provides guaranteed periodic background execution. A DTS answer specifically addressing background Contacts observation points to those same restrictions. This is an inference from the supported lifecycle, not evidence that a particular missed phone alert was caused by suspension. [Contacts notification](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/cncontactstoredidchange), [background execution limits](https://developer.apple.com/forums/thread/685525), [Contacts-specific DTS answer](https://developer.apple.com/forums/thread/765729).

Separate these timestamps in diagnostics: contact change observed, scan started, contact/outbox committed, notification accepted by iOS, notification seen in Notification Center, and user response. The actual contact-save time is not established by the observation timestamp. A short measured observation-to-submission duration cannot establish prompt background discovery.

## Contacts history correctness

Apple's supported reset path is a drop-everything event followed by the current contact inventory. A nil, invalid, or expired token can produce that path; an expired token does **not** necessarily appear as an error. Reconcile snapshots while preserving app-owned notes and confirmations for surviving identifiers. Do not interpret every snapshot add as a newly created contact. Save the result's token only after successful processing. Apple also recommends the `CNChangeHistoryEventVisitor` protocol over checking event classes. [TN3149](https://developer.apple.com/documentation/technotes/tn3149-fetching-change-history-events), [reset event semantics](https://developer.apple.com/documentation/contacts/cnchangehistorydropeverythingevent).

The history enumerator has two failure boundaries: creating it may return nil with `NSError`, and iterating it may throw an Objective-C exception. The original shim only wrapped creation; the Swift loop therefore left iteration exceptions outside its error handling. Consume the enumerator inside Objective-C exception handling and return a complete result or an error. Never publish a partial change set or advance the durable token on that failure. Keep the exception conversion narrow enough that unrelated programming errors are not silently swallowed. [Enumerator contract](https://developer.apple.com/documentation/contacts/cncontactstore/enumeratorforchangehistoryfetchrequest%3Aerror%3A).

Contacts fetches perform I/O and should execute off the main thread. The original `ContactsDiff` actor is an appropriate isolation boundary; protecting the Objective-C enumeration should preserve that property. [CNContactStore](https://developer.apple.com/documentation/contacts/cncontactstore).

## Background refresh and cancellation

`earliestBeginDate` is a lower bound, not a deadline. The audited code requested refresh no earlier than four hours later. A new request replaces an existing pending request; requesting another four-hour delay on every process launch can postpone an earlier eligible refresh. Preserve an earlier pending request when scheduling catch-up. Reducing the requested delay changes eligibility, not iOS's scheduling guarantee. [Earliest begin date](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate), [registration and replacement semantics](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app).

An expiration handler must cancel ongoing work and clean up quickly. The audited refresh handler cancelled its outer task, while concurrent ticks could be waiting on a shared scan; cancellation ownership needs to follow the actual operation. Report refresh failure if capture failed, rather than declaring success solely because the wrapper was not cancelled. Stop optional location enrichment before durable capture or notification work runs out of time. [BGTask expiration](https://developer.apple.com/documentation/backgroundtasks/bgtask/expirationhandler).

`beginBackgroundTask` extends an existing opportunity briefly; it does not create a future contact-change wake. End the assertion when work completes, and make expiration finish promptly. Apple's guidance warns that failing to end it within the allocated time can terminate the app. [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).

## Submission is not banner presentation

`UNUserNotificationCenter.add` success acknowledges successful scheduling. A request without a trigger is eligible immediately, but presentation still follows the person's settings. The original notifier uses the default active interruption level. Active notifications do not bypass Focus or Scheduled Summary; silently changing every contact discovery to time sensitive would misrepresent delayed or low-urgency discoveries. [Submission API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add%28_%3Awithcompletionhandler%3A%29), [interruption levels](https://developer.apple.com/design/human-interface-guidelines/managing-notifications).

Authorization alone does not describe the presentation configuration. Refresh and record alert, sound, lock-screen, Notification Center, and scheduled-delivery settings where available. Provisional permission delivers quietly. Treat these as explanatory diagnostics, without blocking recoverable submission because a banner is disabled. [Permission and feature settings](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

`deliveredNotifications()` returns only notifications still in Notification Center. It is not a permanent receipt ledger. Consequently, stable request identifiers plus a SQLite outbox reduce duplicate submissions but cannot prove exactly-once visible delivery after a crash between iOS acceptance and SQLite acknowledgement followed by the user clearing the notification. Keep the durable outbox and describe its guarantee accurately. [Delivered notifications](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29).

## Physical iPhone evidence

Connect and unlock the phone, establish trust if requested, and inspect the existing installation before installing a replacement build. Apple supports collecting crash reports from TestFlight and devices and using Console logs for problems that do not crash. A debugger can mask lifecycle failures, including watchdog termination, so reproduce ordinary background behavior with the app launched from the phone's Home Screen. [Crash reports and device logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs), [testing a release build](https://developer.apple.com/documentation/xcode/testing-a-release-build).

1. Start macOS Console, select the iPhone, and filter `subsystem:sh.harivan.touchtips`. Reproduce a uniquely identifiable contact addition, noting phone time and foreground/background/lock state. Apple DTS demonstrates that unified logs can be streamed for an app launched independently of Xcode. Existing interpolated private values may appear redacted; retain privacy for contact details. [Console reproduction](https://developer.apple.com/forums/thread/727380).
2. Inspect device/app visibility with `xcrun devicectl list devices` and `xcrun devicectl device info apps --device <device>`. The installed tool, version `518.33`, supports `appDataContainer` and `systemCrashLogs` domains. Its help verifies this targeted, read-only container attempt:

   ```sh
   xcrun devicectl device info files --device <device> \
     --domain-type appDataContainer --domain-identifier sh.harivan.touchtips
   xcrun devicectl device copy from --device <device> \
     --domain-type appDataContainer --domain-identifier sh.harivan.touchtips \
     --source 'Library/Application Support' --destination <local-directory>
   ```

   Apple also documents Xcode > Devices and Simulators > device > app > Download Container. A TestFlight installation's full-container access remains an empirical boundary: the Apple sources reviewed do not promise it. Record the actual result instead of asserting the SQLite database is accessible. [Apple container workflow](https://developer.apple.com/documentation/metal/creating-binary-archives-from-device-built-pipeline-state-objects).
3. If container extraction is denied, continue with Console, crash reports, or an app-provided diagnostic export. Apple's TestFlight debugging guidance recommends crash logs and device Console output. Debugger attachment depends on `get-task-allow`; do not assume a distribution build can be debugged like a development build. [TestFlight debugging](https://developer.apple.com/library/archive/qa/qa1764/), [entitlement meaning](https://developer.apple.com/library/archive/technotes/tn2415/_index.html).
4. libimobiledevice provides `idevicesyslog` and `idevicecrashreport`; use `--keep` when copying crash reports. New upstream versions can request a log archive with `idevicesyslog archive`, but verify the installed version's help before relying on that option. These tools use device services; their existence does not guarantee access to a TestFlight sandbox. [Upstream tools](https://github.com/libimobiledevice/libimobiledevice), [syslog manual](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicesyslog.1), [crash-report implementation](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/idevicecrashreport.c).

If historical logs are insufficient, reproduce the issue and collect a sysdiagnose promptly. Apple documents extracting `system_logs.logarchive` and narrowing it by event timestamps, process, and subsystem. No log tool can reconstruct an event that the app never recorded and the system no longer retains. [Sysdiagnose workflow](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer).

Local verification later in this review: the connected iPhone's existing 0.1.1 (build 1) installation
allowed app-container reads, and installed libimobiledevice 1.4.0 successfully retrieved a log archive
with `idevicesyslog archive`. This establishes access for that installation, not for every TestFlight
or App Store installation. `just log` now uses the tool's process filter directly, removing an extra
format-dependent text filter that could hide valid app logs.
