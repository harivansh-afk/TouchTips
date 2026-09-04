import Foundation
import Testing
@testable import TouchedTipsCore

@Suite struct StatsTests {
    let now = t("2026-09-02T12:00")

    private func beat(_ source: WakeSource, _ at: String, battery: Double? = nil) -> Heartbeat {
        Heartbeat(source: source, at: t(at), batteryLevel: battery)
    }

    @Test func uptimeIsTheShareOfFiveMinuteSlotsWithABeat() {
        // 288 slots in a day. Three beats in three different slots.
        let beats = [beat(.presence, "2026-09-02T11:00"), beat(.presence, "2026-09-02T11:05"), beat(.launch, "2026-09-02T11:10")]
        let stats = CaptureStats.make(from: beats, now: now)
        #expect(abs(stats.uptime - 3.0 / 288.0) < 1e-9)
    }

    @Test func wakesExcludePresenceAndSortByCount() {
        let beats = [
            beat(.presence, "2026-09-02T10:00"), beat(.fence, "2026-09-02T10:10"),
            beat(.contacts, "2026-09-02T10:20"), beat(.contacts, "2026-09-02T10:30"),
        ]
        let stats = CaptureStats.make(from: beats, now: now)
        #expect(stats.wakes.map(\.source) == [.contacts, .fence])
        #expect(stats.wakes.map(\.count) == [2, 1])
    }

    @Test func batteryCountsOnlyDropsAndIgnoresCharging() {
        let beats = [
            beat(.presence, "2026-09-02T08:00", battery: 0.9),
            beat(.presence, "2026-09-02T09:00", battery: 0.8),
            beat(.presence, "2026-09-02T10:00", battery: 1.0),
            beat(.presence, "2026-09-02T12:00", battery: 0.9),
        ]
        let stats = CaptureStats.make(from: beats, now: now)
        // 20 points lost over 4 hours.
        #expect(abs((stats.batteryPerHour ?? 0) - 5.0) < 1e-9)
    }

    @Test func beatsOlderThanADayAreIgnored() {
        let beats = [beat(.launch, "2026-08-30T12:00", battery: 0.5)]
        let stats = CaptureStats.make(from: beats, now: now)
        #expect(stats.uptime == 0)
        #expect(stats.wakes.isEmpty)
        #expect(stats.batteryPerHour == nil)
    }
}
