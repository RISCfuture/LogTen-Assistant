import Audit
import FlightSources
import Foundation
import LogbookModel
import Testing
import Tracks

@Suite
struct `FlySto matching` {
  private let matcher = EvidenceMatcher()

  @Test
  func `matches a record to the one entry with the same aircraft, route and times`() {
    let matches = matcher.matchExports([record()], to: [flight("A"), flight("B", tail: "N222BB")])

    #expect(matches.map(\.status) == [.matched])
    #expect(matches[0].flightID == "A")
    #expect(matches[0].selected?.distanceMinutes == 0)
  }

  @Test
  func `rejects an entry whose airport disagrees but accepts K-prefixed spellings`() {
    let wrongRoute = flight("A", to: "OAK")

    #expect(matcher.matchExports([record()], to: [wrongRoute])[0].status == .unmatched)
    #expect(
      matcher.matchExports([record(from: "SQL", to: "RHV")], to: [flight("A")])[0].status
        == .matched
    )
  }

  @Test
  func `breaks a tie only when the best entry is 20 minutes closer`() {
    let near = flight("A")
    let far = flight(
      "B",
      out: "2026-10-12T14:40:00Z",
      off: "2026-10-12T14:52:00Z",
      on: "2026-10-12T15:38:00Z",
      in: "2026-10-12T15:45:00Z"
    )
    let close = flight(
      "C",
      out: "2026-10-12T14:20:00Z",
      off: "2026-10-12T14:32:00Z",
      on: "2026-10-12T15:18:00Z",
      in: "2026-10-12T15:25:00Z"
    )

    #expect(matcher.matchExports([record()], to: [near, far])[0].flightID == "A")
    let ambiguous = matcher.matchExports([record()], to: [near, close])[0]
    #expect(ambiguous.status == .ambiguous)
    #expect(ambiguous.candidates.map(\.flightID) == ["A", "C"])
  }

  @Test
  func `makes both records ambiguous when they select the same entry`() {
    let matches = matcher.matchExports([record("one"), record("two")], to: [flight("A")])

    #expect(matches.map(\.status) == [.ambiguous, .ambiguous])
    #expect(matches.allSatisfy { $0.flightID == nil })
  }

  @Test
  func `falls back to date and a complete route when neither side has times`() {
    let untimed = flight("A", out: nil, off: nil, on: nil, in: nil)
    let recorded = record(out: nil, takeoff: nil, landing: nil, in: nil, takeoffs: 1, landings: 1)

    let match = matcher.matchExports([recorded], to: [untimed])[0]
    #expect(match.selected?.isDateOnly == true)
    #expect(match.status == .matched)
  }

  @Test
  func `reads aliases as the same aircraft`() {
    let aliased = EvidenceMatcher(aircraft: ["N111AA": AircraftSettings(aliases: ["N999ZZ"])])

    #expect(
      matcher.matchExports([record(tail: "N999ZZ")], to: [flight("A")])[0].status == .unmatched
    )
    #expect(aliased.matchExports([record(tail: "n999zz")], to: [flight("A")])[0].status == .matched)
  }

  @Test
  func `matches by two UTC anchors even when the route is wrong`() {
    let wrongRoute = flight("A", from: "XYZ", to: "ABC")

    let match = matcher.matchByTime([record()], to: [wrongRoute])[0]

    #expect(match.flightID == "A")
    #expect(match.candidates[0].anchors == 4)
  }

  @Test
  func `matches by time only with two anchors, within tolerance and without time issues`() {
    let oneAnchor = flight("A", out: "2026-10-12T14:10:00Z", off: nil, on: nil, in: nil)
    let faraway = flight(
      "B",
      out: "2026-10-12T17:10:00Z",
      off: "2026-10-12T17:22:00Z",
      on: nil,
      in: nil
    )

    #expect(matcher.matchByTime([record()], to: [oneAnchor, faraway])[0].status == .unmatched)
    #expect(
      matcher.matchByTime([record(timeIssues: [.blockTime])], to: [flight("C")])[0].status
        == .unmatched
    )
  }

  @Test
  func `leaves near-identical entries ambiguous`() {
    let first = flight("A")
    let second = flight(
      "B",
      out: "2026-10-12T14:12:00Z",
      off: "2026-10-12T14:24:00Z",
      on: "2026-10-12T15:10:00Z",
      in: "2026-10-12T15:17:00Z"
    )

    let match = matcher.matchByTime([record()], to: [first, second])[0]

    #expect(match.status == .ambiguous)
    #expect(match.flightID == nil)
  }
}

@Suite
struct `Segment correlation` {
  private let correlator = SegmentCorrelator()
  private let segment = flightSegment(startingAt: "2026-10-12T14:21:00Z", cruiseSeconds: 2_740)

  @Test
  func `matches a segment to the one entry it overlaps`() throws {
    let result = try correlator.correlate(
      [segment],
      with: [flight("A"), flight("B", tail: "N222BB")]
    )

    #expect(result.matches.map(\.status) == [.matched])
    #expect(result.matches[0].flightIDs == ["A"])
    #expect(result.matches[0].candidates[0].score >= 0.65)
    #expect(result.findings.isEmpty)
  }

  @Test
  func `weighs overlap, start proximity and duration`() throws {
    let result = try correlator.correlate([segment], with: [flight("A")])
    let candidate = try #require(result.matches[0].candidates.first)
    let observed = segment.end.timeIntervalSince(segment.start)
    let logged = 65.0 * 60
    let expected = 0.35 + 0.25 * (1 - 11.0 * 60 / 3_600) + 0.2 * (observed / logged)

    #expect(abs(candidate.score - expected) < 0.001)
    #expect(candidate.overlapSeconds == observed)
    #expect(candidate.startDeltaSeconds == 660)
  }

  @Test
  func `reports activity with no entry for the aircraft as unmatched`() throws {
    let result = try correlator.correlate([segment], with: [flight("A", tail: "N222BB")])

    #expect(result.matches[0].status == .unmatched)
    #expect(result.findings.map(\.rule) == [.unmatchedTelemetry])
    #expect(result.findings[0].recordIDs.isEmpty)
  }

  @Test
  func `ignores unmatched activity for aircraft flown by others`() throws {
    let shared = SegmentCorrelator(aircraft: [
      "N111AA": AircraftSettings(ignoresUnmatchedActivity: true)
    ])

    let result = try shared.correlate([segment], with: [])

    #expect(result.matches[0].status == .unmatched)
    #expect(result.findings.isEmpty)
  }

  @Test
  func `calls two equally good entries ambiguous`() throws {
    let result = try correlator.correlate([segment], with: [flight("A"), flight("B")])

    #expect(result.matches[0].status == .ambiguous)
    #expect(result.matches[0].flightIDs.isEmpty)
    #expect(result.findings.map(\.rule) == [.ambiguousCorrelation])
    #expect(result.findings[0].recordIDs == ["A", "B"])
  }

  @Test
  func `requires event assignment when a segment spans separate entries`() throws {
    let first = flight(
      "A",
      out: "2026-10-12T14:15:00Z",
      off: nil,
      on: nil,
      in: "2026-10-12T14:45:00Z"
    )
    let second = flight(
      "B",
      out: "2026-10-12T14:50:00Z",
      off: nil,
      on: nil,
      in: "2026-10-12T15:15:00Z"
    )

    let result = try correlator.correlate([segment], with: [first, second])

    #expect(result.matches[0].requiresEventAssignment)
    #expect(result.matches[0].status != .matched)
  }

  @Test
  func `scores an entry without block times by date alone`() throws {
    let untimed = flight("A", out: nil, off: nil, on: nil, in: nil)

    let result = try correlator.correlate([segment], with: [untimed])

    #expect(result.matches[0].candidates[0].isDateOnly)
    #expect(result.matches[0].candidates[0].score == 0.3)
    #expect(result.matches[0].status == .ambiguous)
  }

  @Test
  func `applies overrides and rejects unknown entries`() throws {
    let manual = CorrelationOverride(segmentID: segment.id, flightIDs: ["A", "B"])

    let result = try correlator.correlate(
      [segment],
      with: [flight("A"), flight("B")],
      overrides: [manual]
    )
    #expect(result.matches[0].status == .manual)
    #expect(result.matches[0].flightIDs == ["A", "B"])

    let unknown = CorrelationOverride(segmentID: segment.id, flightIDs: ["missing"])
    #expect(throws: EvidenceError.unknownOverrideFlight("missing")) {
      try correlator.correlate([segment], with: [flight("A")], overrides: [unknown])
    }
  }
}
