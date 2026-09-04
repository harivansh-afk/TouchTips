import Foundation
import Testing
@testable import TouchedTipsCore

struct NoticeTimingTests {
    let heard = t("2026-09-02T12:00")

    @Test func stagesAreConsecutiveGapsAndSkipMissingStamps() {
        let timing = NoticeTiming(
            heard: heard, ticked: heard + 0.3, fixed: nil, resolved: heard + 2.5, named: heard + 3.1,
            posted: heard + 3.2
        )
        #expect(timing.stages.map(\.name) == ["coalesce", "resolve", "name", "post"])
        #expect(timing.stages.map { ($0.seconds * 10).rounded() / 10 } == [0.3, 2.2, 0.6, 0.1])
        #expect(abs(timing.total - 3.2) < 1e-6)
    }

    @Test func roundTripsThroughJSONWithSubsecondPrecision() throws {
        let timing = NoticeTiming(heard: heard, ticked: heard + 0.317, fixed: heard + 1.9, posted: heard + 4.25)
        let back = try NoticeTiming.decode(timing.encoded())
        #expect(abs(back.ticked.timeIntervalSince(heard) - 0.317) < 0.002)
        #expect(back.fixed != nil)
        #expect(back.resolved == nil)
        #expect(abs(back.total - 4.25) < 0.002)
    }
}
