// What the heartbeat table says about the last day. Pure; the Settings sheet shows it.

import Foundation

public struct CaptureStats: Hashable, Sendable {
    public struct Wake: Hashable, Sendable {
        public var source: WakeSource
        public var count: Int

        public init(source: WakeSource, count: Int) {
            self.source = source
            self.count = count
        }
    }

    /// Share of `bucket`-long slots in the last `span` with at least one heartbeat. How often the process was resident.
    public var uptime: Double
    /// Wakes by source over the span, presence excluded, most frequent first.
    public var wakes: [Wake]
    /// Battery points lost per hour across the span, from the levels heartbeats recorded. nil when it never fell.
    public var batteryPerHour: Double?

    public static let span: TimeInterval = 24 * 3600
    public static let bucket: TimeInterval = 5 * 60

    public init(uptime: Double, wakes: [Wake], batteryPerHour: Double?) {
        self.uptime = uptime
        self.wakes = wakes
        self.batteryPerHour = batteryPerHour
    }

    public static func make(from heartbeats: [Heartbeat], now: Date) -> CaptureStats {
        let start = now.addingTimeInterval(-span)
        let recent = heartbeats.filter { $0.at >= start && $0.at <= now }.sorted { $0.at < $1.at }

        var buckets = Set<Int>()
        for beat in recent {
            buckets.insert(Int(beat.at.timeIntervalSince(start) / bucket))
        }
        let uptime = Double(buckets.count) / (span / bucket)

        var counts: [WakeSource: Int] = [:]
        for beat in recent where beat.source != .presence {
            counts[beat.source, default: 0] += 1
        }
        var wakes = counts.map { Wake(source: $0.key, count: $0.value) }
        wakes.sort { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.source.rawValue < b.source.rawValue
        }

        var lost = 0.0
        var previous: Double?
        for beat in recent {
            guard let level = beat.batteryLevel else { continue }
            if let previous, level < previous { lost += previous - level }
            previous = level
        }
        var hours = 0.0
        if let first = recent.first, let last = recent.last {
            hours = last.at.timeIntervalSince(first.at) / 3600
        }
        let batteryPerHour: Double? = lost > 0 && hours > 0 ? lost * 100 / hours : nil

        return CaptureStats(uptime: uptime, wakes: wakes, batteryPerHour: batteryPerHour)
    }
}
