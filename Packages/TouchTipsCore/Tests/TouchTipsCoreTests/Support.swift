import Foundation
import TouchTipsCore

/// `t("2026-09-02T10:00")` in UTC.
func t(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    formatter.timeZone = TimeZone(identifier: "UTC")
    guard let date = formatter.date(from: text) else { fatalError("bad test date \(text)") }
    return date
}

func visit(_ placeID: Int64, _ start: String, _ end: String, source: VisitSource = .live) -> Visit {
    Visit(placeID: placeID, start: t(start), end: t(end), source: source)
}

func add(_ id: String = "c1", _ start: String, _ end: String) -> ContactAdd {
    ContactAdd(contactID: id, seenStart: t(start), seenEnd: t(end))
}
