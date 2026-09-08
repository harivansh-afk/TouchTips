# Architecture review: September 8, 2026

The local architecture is a sensible foundation: Contacts owns identities; GRDB owns meetings,
notes, location evidence, the scan cursor, and a durable notification outbox. The pure core can be
tested independently of iOS. Notification routing, storage-open failure handling, and field-level
meeting confirmation already have useful safeguards. A server or a wholesale architecture rewrite
would not fix the observed classes of failure.

The weak points were task ownership, ordering, retries, and assumptions about background execution.
This review follows the iOS capture, persistence, resolver, notification, permission, navigation,
Add/edit, geocoding, and diagnostic paths. It also checks the build configuration and the separate
static support/privacy website. UI appearance is outside the requested scope.

## Confirmed defects and changes

| Priority | Trigger and original behavior | Change |
| --- | --- | --- |
| High | One `UNUserNotificationCenter.add` or acknowledgement failure exited the entire queue, leaving unrelated people unprocessed. Retry depended on a later wake. | Isolate each record; continue the batch; retry failures after two and five seconds, then leave them durable for the next wake. |
| High | A second `deliverPending` caller returned immediately while another caller was submitting. A background caller could finish its execution window too early. | Callers await the same task, including coalesced follow-up passes. Cancellation follows the actual task. A live caller joining cancelled work starts a new drain after it unwinds. |
| High | Every process launch submitted `now + 4 hours`, replacing any earlier refresh request. | Keep earlier requests; advance obsolete four-hour requests to fifteen-minute eligibility. Scheduling calls coalesce. iOS still chooses whether and when to execute. |
| High | A fresh contact and its outbox entry waited for an optional location request, for up to eight seconds. | Commit and notify first. A separate cancellable enrichment task updates eligible unconfirmed meetings. Reset waits for that task so it cannot repopulate deleted data. |
| High | The Contacts shim only created an enumerator; iteration occurred in Swift, beyond an Objective-C exception boundary. | Consume the full batch inside the bridge. An enumeration exception produces an error, never a partial batch or a new durable token. |
| High | Contacts/SQLite failures before outbox commit needed a later wake. A wake received while a cancelled scan unwound could be discarded. | Bounded scan retries retain the unchanged cursor. A queued wake survives cancelled work. Refresh completion reflects the final scan result, and expiration releases its assertion immediately. |
| Medium | Repeated debounce calls could keep pushing the scan later, including a slower movement wake replacing a prompt Contacts scan. | Keep the earliest deadline and preserve Contacts as the preferred source. |
| Medium | Old notices were drained before a Contacts deletion was ingested. A saved batch could also contain someone forgotten during an earlier asynchronous submission. | Reconcile Contacts first; recheck outbox membership with the person read. If removal happens during submission, withdraw the obsolete request. A Contacts failure still allows already-durable notices to drain. |
| High | An in-app Add wrote Contacts first; a SQLite failure followed by Save again created another system contact. Exact-save retries could overwrite a note. | A form-owned save operation retains identity and original time, updates the existing contact on retry, and preserves notes. Selected place, meeting, and outbox commit in one SQLite transaction. |
| Medium | A callback heard after launch was treated as proof that an addition happened after launch. Queued callbacks can describe older changes. | Derive discovery intervals only from successful reads. Clamp backward clock changes so intervals cannot invert. Existing historical guesses cannot be reconstructed from absent evidence. |
| Medium | A note typed just before backgrounding could remain only in a 600 ms debounce task; the view need not disappear on suspension. | Flush pending note text when the scene becomes inactive. |
| Low | Heartbeat rows accumulated indefinitely; an inclusive time boundary could report more than 100% sampled coverage. | Retain seven days of diagnostic heartbeats and clamp the boundary bucket. No meeting or visit history is expired. |

The notification outbox remains the source of pending work. No network lookup, visual transition,
or view lifetime determines whether a newly discovered contact gets recorded. New adapters are
small injected closures around Contacts, location, notification delivery, and refresh scheduling;
they allow real ordering/failure tests without substituting a second application architecture.

## Physical-phone evidence

The iPhone 17 Pro connected during validation. Its existing installation reports 0.1.1 (build 1).
The app database, WAL, preferences, and available system-log archive were copied read-only before
any installation changes. The copied database passed SQLite integrity checking and had no pending
notices at the snapshot. Raw phone data stays in the ignored local `build/phone-audit-20260908/`
directory, outside the review commit.

The phone evidence confirms three distinct causes of inconsistent timing or presentation:

- Seven logged scan-to-location-completion times varied from 3 milliseconds to 7.604 seconds. The latest saved
  observation-to-submission timing was 7.755 seconds, including 7.361 seconds waiting for location.
  This delay is removed from the new capture/notification path.
- The system recorded a TouchTips notification suppressed by a Focus mode. The other ten recorded
  Focus decisions did not suppress interruption. Notification authorization, alerts, sounds, and
  lock-screen delivery were enabled; Scheduled Summary was disabled in the captured settings.
  Retrying that suppressed alert would not be an appropriate way to bypass the user's Focus policy.
- The scheduler logs show repeated cancellation/replacement of background refresh requests with
  new four-hour eligibility windows. Location Always authorization and presence were enabled;
  they did not prevent recorded suspended process states. The revised scheduler preserves earlier
  requests and requests fifteen-minute eligibility, without promising a wake deadline.

The captured app logs contain no reported capture/submission failures. The failure-isolation and
retry changes are therefore proven by regression tests, not attributed to these particular phone
events. This branch has not been installed on the physical phone; before/after phone behavior remains
to be verified.

The revised logs include notification authorization, alert/sound/lock-screen/Notification Center/
summary settings, queue size, submission age, Contacts permission skips, scan outcomes, and location
enrichment separately. They avoid publishing contact names, contact identifiers, or coordinates in
the diagnostic fields. `lastNotice` measures observed change/queue-to-submission time; it does not
measure the unknown system-contact save time or prove banner display.

For the next reproduction, record the actual contact-save time, app state, discovery log,
submission log, and visible notification separately. Repeat external Contacts save, NameDrop,
in-app Add, lock/background/foreground, permission restoration, and notification taps. See
[Apple constraints and diagnostic commands](apple-notification-constraints.md) and
[the physical-device procedure](notification-testing.md#physical-iphone-release-check).

## Remaining architecture limits and review observations

- There is no supported guaranteed wake for every contact saved externally. Background refresh,
  visits, movement, and the location presence policy provide opportunities to scan; they do not
  establish continuous execution. The fifteen-minute value is eligibility, not a measured cadence.
- iOS acceptance is not a delivery receipt. Focus, Scheduled Summary, provisional authorization,
  and per-feature notification settings can explain quiet or delayed presentation. Ordinary
  contact discoveries remain ordinary notifications; the change does not bypass user settings.
- Stable request IDs reconcile pending/delivered notifications after a crash. If iOS accepted one,
  the process died before SQLite acknowledgement, and the user cleared the notification before
  reconciliation, a later retry can display it again. Exactly-once visible delivery is unavailable
  across that boundary.
- Contacts and SQLite cannot share a transaction. Same-form retries now preserve identity; killing
  the app between the two stores can still lose the explicit time/place selection. The Contacts
  observer can discover the saved person later. A future durable cross-store save journal would be
  required to preserve every draft detail across that interruption.
- Automatic location is a suggestion. Visit matching uses coordinate cells and reported intervals;
  source accuracy and changing visit coordinates can still make a place imprecise. Matching a
  contact-store addition does not prove a physical meeting. User confirmations retain priority.
- The default continuous location policy remains a product/battery tradeoff requiring phone
  measurements. Heartbeat coverage samples execution opportunities, and sampled battery loss is
  whole-device loss; neither proves exact app uptime or app-attributable energy use.
- Geocoding already retries transient failures, protects user-supplied names, and runs independently
  of capture. Storage opening already fails visibly instead of substituting an in-memory database.
  Those boundaries are preserved. Timeline import is currently an unwired core capability, not part
  of notification delivery.
- The support/privacy website is static and separate from capture; it introduces no backend in this
  pipeline. Generated Xcode files remain generated. No dependencies or deployment settings were
  intentionally changed.

Apple sources supporting platform claims are collected in
[the accompanying primary-source research](apple-notification-constraints.md).

## Validation

- `nix develop -c just check`: 56 core tests and the signed iPhone build passed, with no build warnings.
- Hosted simulator suite: 62 passed, zero failures or skips. Includes real Contacts observation,
  an injected Objective-C enumeration exception, blocked location, concurrent delivery, retry,
  cancellation, deletion races, refresh scheduling, and cross-store Add retry.
- Five real notification UI cases passed: warm tap/Back, cold tap, removed-contact fallback,
  external Contacts save/tap, and in-app Add/save/tap. The tests exercise the actual notification
  center, not a simulated delegate callback.
- All 17 changed/new Swift files pass formatting lint. Full-repository lint reports 18 inherited
  files, with no failures in files changed by this review; unrelated formatting was left alone.
- `git diff --check` passed. No dependency versions or database migrations changed.

The final branch includes the UI commits through `c72464e`, which landed during this review. The
signed build and hosted suite were rerun after integration. Result bundles are in the main checkout's
ignored `build/` directory; the final validation bundles use the `architecture-audit-integrated-`
prefix.

The first hosted run exposed an obsolete fixture that placed a synthetic person only in SQLite;
the new Contacts-first reconciliation correctly removed it. After correcting the fixture, an
incremental simulator install still ran the old bundle. Explicitly reinstalling the current bundle
and running the build/test action produced a green 59-test result. The integrated suite subsequently
passed all 62 tests, including the additional UI presentation tests from `main`.

All test contacts and permission changes were confined to the dedicated TouchTips Notifications
simulator. Phone access was diagnostic only, without a debugger or an app replacement.
