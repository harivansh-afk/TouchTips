# Meeting confirmation and person swipes

A bright filled dot means the user confirmed the meeting; a dim filled dot means suggested details.
An undocumented contact has an empty dot and no placeholder subtitle. The same state drives People, timeline, search and map emphasis.
Precision and completeness remain separate: a confirmed record may have an approximate date or no place.

Date and place confirmation are stored separately. Changing a field accepts that field, while the
explicit **Confirm meeting** action accepts the whole record. Manually edited records retain their
existing protection against automatic replacement. Add through TouchTips records a confirmed meeting.

Automatic resolution retains the contact discovery interval rather than narrowing it to a visit or
current location. Point fixes are considered only within intervals of at most 60 seconds; this is a
conservative matching policy, not a guarantee of when people met. Current fixes are requested only
for live contact changes, with invalid or stale samples rejected. Notifications distinguish new
contacts from recorded meetings.

The additive v5 migration preserves manual edits. Older records did not distinguish field edits from
whole-meeting confirmation, so only records with the unambiguous in-app Add signature migrate as
confirmed. Others can be reviewed without losing their values. Automatic records are re-resolved
from their retained discovery intervals.

## Swipes

The implementation follows native `.swipeActions` in Mixbridge's `Components/TrackRow.swift`, with
empty visible labels and explicit accessibility labels. Timeline rows now use a native List with
the existing spine and month markers. People and timeline use Mixbridge's 44-point content height,
12-point horizontal gap, and four points of vertical row spacing on each side. Removing the previous
extra internal padding lets native swipe controls retain their oval proportions.

The note sheet has no opaque content background and starts at a compact detent, leaving the system
Liquid Glass presentation visible. See [Apple's sheet guidance](https://developer.apple.com/videos/play/wwdc2025/323/?time=392).

- Right: a white note icon on Notes yellow (`#E3AF09`), opening a compact, focused Liquid Glass sheet with
  the app's check icon. Dismissal flushes pending edits.
- Left: a white trash icon on system red, asking to forget the meeting and note.
  The phone contact stays. Forget is omitted when there is no TouchTips data to remove.
- Full swipe opens the action; Forget still requires confirmation. Cancel changes nothing.

Forget removes the meeting, note and pending notification atomically. It retains the person record,
so a repeated Contacts addition, history reset or visit re-resolution cannot recreate the meeting
for that existing contact.

## Validation

Core regression tests cover legacy migration, field confirmation, delayed discovery, preserved
intervals, map emphasis, forgetting across rescans, and rollback on storage failure. Hosted tests
cover range presentation before and after confirmation. UI tests cover note focus and persistence
in People, timeline and search; Forget cancellation and confirmation; and native swipe appearance
and timeline scrolling.

The repository-wide formatter check also fails on untouched main with the flake's current
SwiftFormat. Unrelated formatting changes are excluded from this change; edited Swift files are
checked separately.

Verified locally on 2026-09-05:

- 51 core tests passed.
- 44 hosted app tests and all 5 swipe UI tests passed on the isolated TouchTips QA simulator.
- `nix develop -c just check` passed, including the device build with warnings treated as failures.
- All 24 edited Swift files passed lint; baseline main still fails the repository-wide formatter check.
- Reviewed the native note and trash reveal screenshots under `build/review/`.

Styling revision: the note round-trip, native swipe appearance, and repeated timeline scroll-to-top
UI tests passed. Both simulator and device builds completed without warnings; all three edited
Swift files passed lint. Reviewed the yellow/system-red oval actions and translucent note
sheet with the check icon in the updated screenshots under `build/review/`.


## Row layout repair

Headings are ordinary rows rather than empty sections. Every contact row has the same four-point
vertical padding and one separator drawn from the name inset to the trailing margin; native row
separators are hidden, avoiding section-boundary lines. Undocumented contacts show their name,
avatar and an empty dot, without repeating “No meeting details”.

The timeline retains its original 24-point marker column within the 16-point list margin, with a
12-point gap before the avatar. The spine is 28 points from the screen edge and the avatar starts
at 52 points. Native oval swipe controls, system red, and the clear compact note sheet remain.

The Notes action uses sRGB `#E3AF09`, sampled from the flat yellow chevron in
[Apple’s Notes App Store screenshot](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/d6/66/47/d6664789-9276-5995-e635-1cbf606299c8/3_Notes_list_screen.PNG/1290x2796bb.png).
This matches that published reference rather than assuming generic system yellow is Notes’ accent.

The row repair passed five targeted UI checks: note persistence, undocumented presentation and note
access after scrolling, swipe appearance, and repeated scroll-to-top in default and timeline layouts.
The swipe check was repeated after correcting the marker background alignment. Both builds were
warning-free, and all nine edited Swift files passed formatting checks. Installed and launched on
the connected iPhone 17 Pro.

Device-only follow-up: restored the original timeline gutter after the compact margin proved too
tight on the phone. Suggested details now use a dim filled dot, leaving the empty ring exclusively
for undocumented contacts. This follow-up is built and installed directly on iPhone; no simulator
was used for validation.
