import Foundation
import TouchedTipsCore

/// `t("2026-09-02T10:00")` in UTC.
func t(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    guard let date = formatter.date(from: text) else { fatalError("bad test date \(text)") }
    return date
}

func visit(_ placeID: Int64, _ start: String, _ end: String, source: VisitSource = .live) -> Visit {
    Visit(placeID: placeID, start: t(start), end: t(end), source: source)
}

func add(_ start: String, _ end: String, id: String = "c1") -> ContactAdd {
    ContactAdd(contactID: id, seenStart: t(start), seenEnd: t(end))
}
