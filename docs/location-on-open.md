# Location while the app is open

TouchTips 1.1 was rejected under guideline 2.5.4 for declaring the `location` background mode, and
#60 removed location entirely. This brings back one narrow use, with no background mode: the place
you are in, read only while TouchTips is open, for a contact you have just saved.

## What reads location

Only `LocationAccess`, with While Using permission (`NSLocationWhenInUseUsageDescription`, no Always
key, `UIBackgroundModes` stays `[fetch]`). A fix counts only if it is under a minute old and within
100 m; Approximate Location is treated as no location.

1. **Opening the app** (`PlaceOnOpen`). On every foreground, and after a foreground scan records new
   people, contacts whose discovery interval started in the last 20 minutes and have no place get
   the place you are in: the nearest Apple Maps place of interest, else the street address. It is a
   suggestion (`tier = .inferred`, `placeConfirmed = false`), drawn as a dim dot until confirmed.
   A place the user chose is never replaced, and a meeting added in the app is left as saved.
2. **Add sheet.** Nearby places lead the chips and the nearest is preselected; it shows on the map
   before you save.
3. **Person screen, meeting today.** Nearby places join the chips. Nothing is chosen for you,
   because a choice there saves at once.

Permission is asked in onboarding, from Settings, or by tapping the **Near me** chip. Nothing asks
on its own when the app opens.

## Notifications

A scan that finds new people while the app is open waits up to 8 s for the place before posting, so
the banner can already say where. In the background there is no fix, and the notice asks "Where?".
The notice carries the place it showed; **That's right** confirms the date, and the place only if
it is still the one shown. A place suggested after the notice was posted stays a suggestion.

## Why 20 minutes

The discovery interval is bounded below by the last Contacts read. When it started more than 20
minutes before the fix, the user may have left the place, so nothing is suggested. Background
refresh keeps the interval short for people who leave the app closed.

## App Review

- 2.5.4: no background modes beyond `fetch`.
- 5.1.1: the purpose string says what location is for; the app works fully without it.
- 5.1.5: location is used only for the feature that needs it.
- App Store Connect, App Privacy: declare Precise Location, used for App Functionality, not linked
  for tracking. If Connect syncs places to touchtips.app, that is collection and must be declared.
- Review notes: "Location (While Using) suggests where you met a contact you just saved. Add a
  contact in Contacts, open TouchTips within 20 minutes, and the person shows the place you are in."
