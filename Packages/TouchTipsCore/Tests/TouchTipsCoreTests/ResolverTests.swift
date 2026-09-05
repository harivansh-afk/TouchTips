import Foundation
import Testing
@testable import TouchTipsCore

@Suite struct ResolverTests {
    let now = t("2026-09-02T12:00")

    @Test func witnessedWhenAVisitContainsTheAdd() {
        let visits = [visit(7, "2026-09-02T10:12", "2026-09-02T11:40")]
        let meet = Resolver.meet(for: add("2026-09-02T10:41", "2026-09-02T11:02"), visits: visits, now: now)
        #expect(meet.tier == .witnessed)
        #expect(meet.placeID == 7)
        #expect(meet.start == t("2026-09-02T10:41"))
        #expect(meet.end == t("2026-09-02T11:02"))
        #expect(meet.precision == .day)
    }

    @Test func witnessedIntervalIsClippedToTheVisit() {
        let visits = [visit(7, "2026-09-02T10:50", "2026-09-02T11:40")]
        let meet = Resolver.meet(for: add("2026-09-02T09:00", "2026-09-02T11:00"), visits: visits, now: now)
        #expect(meet.tier == .witnessed)
        #expect(meet.start == t("2026-09-02T10:50"))
        #expect(meet.end == t("2026-09-02T11:00"))
    }

    @Test func largestOverlapWinsAmongSeveralVisits() {
        let visits = [
            visit(1, "2026-09-02T09:55", "2026-09-02T10:05"),
            visit(2, "2026-09-02T10:05", "2026-09-02T11:30"),
        ]
        let meet = Resolver.meet(for: add("2026-09-02T10:00", "2026-09-02T11:00"), visits: visits, now: now)
        #expect(meet.placeID == 2)
    }

    @Test func inferredFromTheNearestVisitInsideTheWindow() {
        let visits = [
            visit(3, "2026-09-02T07:00", "2026-09-02T08:30"),
            visit(4, "2026-09-02T12:30", "2026-09-02T13:00"),
        ]
        let meet = Resolver.meet(for: add("2026-09-02T10:00", "2026-09-02T11:00"), visits: visits, now: now)
        #expect(meet.tier == .inferred)
        #expect(meet.placeID == 3)
        #expect(meet.start == t("2026-09-02T10:00"))
    }

    @Test func dateOnlyWhenNothingIsClose() {
        let visits = [visit(3, "2026-09-01T07:00", "2026-09-01T08:30")]
        let meet = Resolver.meet(for: add("2026-09-02T10:00", "2026-09-02T11:00"), visits: visits, now: now)
        #expect(meet.tier == .dateOnly)
        #expect(meet.placeID == nil)
        #expect(meet.addSeenStart == t("2026-09-02T10:00"))
    }

    @Test func aFixInsideTheIntervalOutranksALongerStay() {
        let visits = [
            visit(2, "2026-09-02T08:00", "2026-09-02T18:00"),
            visit(9, "2026-09-02T10:41", "2026-09-02T10:41", source: .fix),
        ]
        let meet = Resolver.meet(for: add("2026-09-02T09:30", "2026-09-02T10:41"), visits: visits, now: now)
        #expect(meet.tier == .witnessed)
        #expect(meet.placeID == 9)
        #expect(meet.precision == .exact)
        #expect(meet.start == t("2026-09-02T10:41"))
        #expect(meet.end == t("2026-09-02T10:41"))
    }

    @Test func aFixOutsideTheIntervalNeverInfers() {
        let visits = [visit(9, "2026-09-02T11:30", "2026-09-02T11:30", source: .fix)]
        let meet = Resolver.meet(for: add("2026-09-02T10:00", "2026-09-02T11:00"), visits: visits, now: now)
        #expect(meet.tier == .dateOnly)
        #expect(meet.placeID == nil)
    }

    @Test func precisionFollowsTheSpan() {
        #expect(Precision.spanning(t("2026-09-02T10:00"), t("2026-09-02T11:00")) == .day)
        #expect(Precision.spanning(t("2026-09-02T10:00"), t("2026-09-10T11:00")) == .month)
        #expect(Precision.spanning(t("2026-01-02T10:00"), t("2026-09-10T11:00")) == .year)
    }

    @Test func initials() {
        #expect(Person.initials(for: "Dev Patel") == "DP")
        #expect(Person.initials(for: "Maya Anne Kapoor") == "MK")
        #expect(Person.initials(for: "Cher") == "C")
        #expect(Person.initials(for: "   ") == "?")
    }
}
