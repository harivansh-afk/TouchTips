// Where the time went between hearing about an add and its notification. Pure; the Settings sheet shows it.

import Foundation

/// The clock stamps of the last add-to-notification run, stored as JSON under `StoreKey.lastNotice`.
public struct NoticeTiming: Codable, Hashable, Sendable {
    /// One stage of the run and how long it took.
    public struct Stage: Hashable, Sendable {
        public var name: String
        public var seconds: TimeInterval
    }

    /// The first `CNContactStoreDidChange` of the burst, or the wake for a relaunch.
    public var heard: Date
    /// The tick began, after the coalesce.
    public var ticked: Date
    /// A precise fix came back. nil when there was no add to witness or the fix timed out.
    public var fixed: Date?
    /// The diff was applied and the meet resolved.
    public var resolved: Date?
    /// The place got a name, or naming was skipped.
    public var named: Date?
    /// The notification request was handed to the system.
    public var posted: Date

    public init(
        heard: Date,
        ticked: Date,
        fixed: Date? = nil,
        resolved: Date? = nil,
        named: Date? = nil,
        posted: Date
    ) {
        self.heard = heard
        self.ticked = ticked
        self.fixed = fixed
        self.resolved = resolved
        self.named = named
        self.posted = posted
    }

    /// Heard to posted.
    public var total: TimeInterval {
        posted.timeIntervalSince(heard)
    }

    /// Consecutive gaps between the stamps that exist, in order. A skipped stage is folded into the next one.
    public var stages: [Stage] {
        let stamps: [(String, Date?)] = [
            ("coalesce", ticked), ("fix", fixed), ("resolve", resolved), ("name", named), ("post", posted),
        ]
        var previous = heard
        var stages: [Stage] = []
        for (name, stamp) in stamps {
            guard let stamp else { continue }
            stages.append(Stage(name: name, seconds: stamp.timeIntervalSince(previous)))
            previous = stamp
        }
        return stages
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> NoticeTiming {
        try JSONDecoder().decode(NoticeTiming.self, from: data)
    }
}
