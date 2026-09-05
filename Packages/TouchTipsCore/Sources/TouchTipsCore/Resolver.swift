// Turns "this contact appeared somewhere in this interval" plus known visits into a Meet.
// Pure. No database, no clock of its own.

import Foundation

/// A contact that did not exist at `seenStart` and did at `seenEnd`.
public struct ContactAdd: Hashable, Sendable {
    public var contactID: String
    public var seenStart: Date
    public var seenEnd: Date

    public init(contactID: String, seenStart: Date, seenEnd: Date) {
        self.contactID = contactID
        self.seenStart = seenStart
        self.seenEnd = seenEnd
    }
}

public enum Resolver {
    /// How far from the add interval a visit may sit and still be the inferred place.
    public static let window: TimeInterval = 2 * 3600

    /// A point location can suggest a place only for a short discovery interval. This is a
    /// conservative matching policy, not proof of a meeting or a platform timing guarantee.
    public static let fixWindow: TimeInterval = 60

    /// Callers pass every visit overlapping `[seenStart - window, seenEnd + window]`.
    ///
    /// A recent fix may suggest a place for a short interval. Stays may suggest a place for
    /// longer intervals. Neither establishes a meeting time or narrows the discovery interval.
    public static func meet(for add: ContactAdd, visits: [Visit], now: Date) -> Meet {
        let overlapping = visits.filter { $0.start <= add.seenEnd && $0.end >= add.seenStart }
        if add.seenEnd.timeIntervalSince(add.seenStart) <= fixWindow,
           let fix = overlapping.filter({ $0.source == .fix }).max(by: { $0.start < $1.start }) {
            return make(add, start: add.seenStart, end: add.seenEnd, placeID: fix.placeID, tier: .witnessed, now: now)
        }

        let stays = overlapping.filter { $0.source != .fix }
        if let visit = stays.max(by: { overlap($0, add) < overlap($1, add) }) {
            return make(add, start: add.seenStart, end: add.seenEnd, placeID: visit.placeID, tier: .witnessed, now: now)
        }

        let nearby = visits.filter { $0.source != .fix && gap($0, add) <= window }
        if let visit = nearby.min(by: { gap($0, add) < gap($1, add) }) {
            return make(add, start: add.seenStart, end: add.seenEnd, placeID: visit.placeID, tier: .inferred, now: now)
        }

        return make(add, start: add.seenStart, end: add.seenEnd, placeID: nil, tier: .dateOnly, now: now)
    }

    private static func make(
        _ add: ContactAdd, start: Date, end: Date, precision: Precision? = nil, placeID: Int64?, tier: Tier, now: Date
    ) -> Meet {
        Meet(
            contactID: add.contactID,
            start: start,
            end: end,
            precision: precision ?? .spanning(start, end),
            placeID: placeID,
            tier: tier,
            userSet: false,
            addSeenStart: add.seenStart,
            addSeenEnd: add.seenEnd,
            computedAt: now
        )
    }

    private static func overlap(_ visit: Visit, _ add: ContactAdd) -> TimeInterval {
        min(add.seenEnd, visit.end).timeIntervalSince(max(add.seenStart, visit.start))
    }

    /// Distance between a non-overlapping visit and the add interval.
    private static func gap(_ visit: Visit, _ add: ContactAdd) -> TimeInterval {
        if visit.end < add.seenStart {
            return add.seenStart.timeIntervalSince(visit.end)
        }
        if visit.start > add.seenEnd {
            return visit.start.timeIntervalSince(add.seenEnd)
        }
        return 0
    }
}
