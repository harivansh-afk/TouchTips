import Foundation
import TouchTipsCore

/// `t("2026-09-02T10:00")` in UTC.
func t(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    guard let date = formatter.date(from: text) else { fatalError("bad test date \(text)") }
    return date
}
