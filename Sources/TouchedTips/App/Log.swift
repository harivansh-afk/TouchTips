import OSLog

enum Log {
    private static let subsystem = "sh.harivan.touchtips"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let geocode = Logger(subsystem: subsystem, category: "geocode")
    static let notify = Logger(subsystem: subsystem, category: "notify")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
