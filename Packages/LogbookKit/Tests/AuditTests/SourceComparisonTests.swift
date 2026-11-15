import Audit
import FlightSources
import Foundation
import LogbookModel
import Testing
import Tracks

@Suite
struct `Source comparison` {
  private let comparison = SourceComparison()
  private let matcher = EvidenceMatcher()

  private let consistentSegment = flightSegment(
    startingAt: "2026-10-12T14:21:00Z",
    cruiseSeconds: 2_740
  )

  private func compare(
    _ flights: [Flight],
    records: [FlyStoRecord] = [],
    segments: [TrackSegment] = [],
    overrides: [CorrelationOverride] = []
  ) throws -> SourceComparisonResult {
    let matches = matcher.matchExports(records, to: flights)
    let correlation = try SegmentCorrelator().correlate(
      segments,
      with: flights,
      overrides: overrides
    )
    return comparison.compare(
      flights: flights,
      records: records,
      matches: matches,
      segments: segments,
      segmentMatches: correlation.matches
    )
  }

  @Test
  func `proposes FlySto's times rounded to the nearest whole minute`() throws {
    let record = record(in: "2026-10-12T15:25:36Z")

    let result = try compare([flight("A")], records: [record])

    let change = try #require(result.findings.first?.corrections.flatMap(\.changes).first)
    #expect(change.new == .date(utc("2026-10-12T15:26:00Z")))
  }

  @Test
  func `proposes FlySto's block-in time when it differs from the logbook`() throws {
    let record = record(in: "2026-10-12T15:25:00Z")

    let result = try compare([flight("A")], records: [record])

    let finding = try #require(result.findings.first)
    #expect(result.findings.count == 1)
    #expect(finding.rule == .telemetryTime)
    #expect(finding.recordIDs == ["A"])
    #expect(finding.evidence["delta_minutes"]?.doubleValue == 10)
    #expect(finding.evidence["event"]?.stringValue == "in")
    #expect(finding.evidence["source"]?.stringValue == "fly_sto")
    #expect(
      finding.corrections.flatMap(\.changes) == [
        FieldChange(
          flightKey: "key-A",
          recordID: "A",
          field: .flightActualArrivalTime,
          old: .date(utc("2026-10-12T15:15:00Z")),
          new: .date(utc("2026-10-12T15:25:00Z"))
        )
      ]
    )
  }

  @Test
  func `proposes a missing block-out time without reconstructing it from other fields`() throws {
    let missing = flight("A", out: nil)

    let result = try compare([missing], records: [record()])

    let finding = try #require(result.findings.first)
    #expect(finding.evidence["delta_minutes"] == .null)
    #expect(finding.evidence["logged"] == .null)
    #expect(finding.corrections.flatMap(\.changes).map(\.field) == [.flightActualDepartureTime])
    #expect(finding.corrections.flatMap(\.changes).map(\.old) == [.null])
  }

  @Test
  func `accepts times within a minute and reports nothing when everything agrees`() throws {
    let result = try compare([flight("A")], records: [record(landing: "2026-10-12T15:08:50Z")])

    #expect(result.findings.isEmpty)
    #expect(result.choices.map(\.agrees).contains(false) == false)
    #expect(result.choices.count == 6)
  }

  @Test
  func `does not add a takeoff or landing time the logbook doesn't have`() throws {
    let result = try compare([flight("A", off: nil, on: nil)], records: [record()])

    #expect(result.findings.isEmpty)
  }

  @Test
  func `reports a count difference without proposing a change`() throws {
    let result = try compare([flight("A", takeoffs: 3)], records: [record()])

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryCount)
    #expect(finding.evidence["logged"] == .integer(3))
    #expect(finding.evidence["observed"] == .integer(1))
    #expect(finding.corrections.isEmpty)
  }

  @Test
  func `reports repeated FlySto rows that disagree and does not fall back to ADS-B`() throws {
    let conflicted = record(takeoffs: nil, conflicts: [.count(.takeoff)])
    let wrongCount = flight("A", takeoffs: 2)

    let result = try compare([wrongCount], records: [conflicted], segments: [consistentSegment])

    let finding = try #require(result.findings.first { $0.rule == .telemetrySourceConflict })
    #expect(finding.evidence["kind"]?.stringValue == "count")
    #expect(finding.evidence["event"]?.stringValue == "takeoff")
    #expect(
      result.findings.contains {
        $0.rule == .telemetryCount && $0.evidence["event"]?.stringValue == "takeoff"
      } == false
    )
  }

  @Test
  func `treats a zero count with a missing boundary as unusable and falls back to ADS-B`() throws {
    let zero = record(takeoff: nil, takeoffs: 0)

    let result = try compare(
      [flight("A", takeoffs: 1)],
      records: [zero],
      segments: [consistentSegment]
    )

    let choice = try #require(result.choices.first { $0.field == .count(.takeoff) })
    #expect(choice.selected == .adsbLol)
    #expect(choice.agrees)
  }

  @Test
  func `compares ADS-B takeoff, landing and full-stop counts against the logbook`() throws {
    let result = try compare([flight("A", fullStops: 2)], segments: [consistentSegment])

    let finding = try #require(result.findings.first)
    #expect(result.findings.count == 1)
    #expect(finding.rule == .telemetryCount)
    #expect(finding.evidence["event"]?.stringValue == "full_stop")
    #expect(finding.evidence["observed"] == .integer(1))
    #expect(finding.evidence["source"]?.stringValue == "adsb_lol")
  }

  @Test
  func `compares ADS-B takeoff time to the logbook within the tolerance`() throws {
    let late = flight("A", off: "2026-10-12T14:35:00Z")

    let result = try compare([late], segments: [consistentSegment])

    let finding = try #require(result.findings.first { $0.rule == .telemetryTime })
    #expect(finding.evidence["event"]?.stringValue == "takeoff")
    #expect(finding.evidence["delta_minutes"]?.doubleValue == -13)
    #expect(finding.corrections.isEmpty)
    let withinTolerance = try compare(
      [flight("A", off: "2026-10-12T14:27:00Z")],
      segments: [consistentSegment]
    )
    #expect(withinTolerance.findings.isEmpty)
  }

  @Test
  func `never takes block times from ADS-B`() throws {
    let result = try compare(
      [flight("A", out: "2026-10-12T13:00:00Z", in: "2026-10-12T17:00:00Z")],
      segments: [consistentSegment]
    )

    #expect(result.choices.contains { $0.field == .time(.out) || $0.field == .time(.in) } == false)
    #expect(result.findings.isEmpty)
  }

  @Test
  func `lets an agreeing FlySto value silence a disagreeing ADS-B one`() throws {
    let logged = flight("A", off: "2026-10-12T14:35:00Z")
    let flySto = record(takeoff: "2026-10-12T14:35:00Z")

    let result = try compare([logged], records: [flySto], segments: [consistentSegment])

    let choice = try #require(result.choices.first { $0.field == .time(.takeoff) })
    #expect(choice.selected == .flySto)
    #expect(choice.observations.map(\.source) == [.flySto, .adsbLol])
    #expect(result.findings.isEmpty)
  }

  @Test
  func `asks about missing block times when ADS-B saw the flight`() throws {
    let unlogged = flight("A", out: nil, in: nil)
    let assigned = CorrelationOverride(segmentID: consistentSegment.id, flightIDs: ["A"])

    let result = try compare([unlogged], segments: [consistentSegment], overrides: [assigned])

    let finding = try #require(result.findings.first { $0.rule == .telemetryMissingTimes })
    #expect(finding.evidence["missing"] == ["out", "in"])
  }

  @Test
  func `drops the missing-times question once FlySto supplies the times, or narrows it`() throws {
    let unlogged = flight("A", out: nil, in: nil)
    let assigned = [CorrelationOverride(segmentID: consistentSegment.id, flightIDs: ["A"])]

    let complete = try compare(
      [unlogged],
      records: [record()],
      segments: [consistentSegment],
      overrides: assigned
    )
    #expect(complete.findings.contains { $0.rule == .telemetryMissingTimes } == false)
    #expect(complete.findings.filter { $0.rule == .telemetryTime }.count == 2)

    let partial = try compare(
      [unlogged],
      records: [record(in: nil)],
      segments: [consistentSegment],
      overrides: assigned
    )
    let question = try #require(partial.findings.first { $0.rule == .telemetryMissingTimes })
    #expect(
      question.evidence["preferred_known_times"]?["out"]?.stringValue == "2026-10-12T14:10:00Z"
    )
  }
}

@Suite
struct `Instruction activity` {
  private let owner = person("owner")
  private let student = person("student")

  private func finding(_ rule: RuleID, flight: String, evidence: JSONValue = [:]) -> Finding {
    Finding(rule: rule, recordIDs: [RecordID(rawValue: flight)], message: "", evidence: evidence)
  }

  @Test
  func `finds entries where the owner instructs or someone else is the student`() throws {
    let flights = [
      flight("instructing", crew: FlightCrew(instructor: owner)),
      flight("with-student", crew: FlightCrew(student: student)),
      flight("own-training", crew: FlightCrew(instructor: student, student: owner)),
      flight("solo")
    ]

    let ids = try InstructionPolicy.instructionalFlightIDs(in: flights, owner: owner.id)

    #expect(ids == ["instructing", "with-student"])
    #expect(throws: EvidenceError.ownerNotIdentified) {
      try InstructionPolicy.instructionalFlightIDs(in: flights, owner: nil)
    }
  }

  @Test
  func `excludes student-attributable findings but keeps aircraft timestamps`() {
    let findings = [
      finding(.telemetryCount, flight: "instructing"),
      finding(.telemetryTime, flight: "instructing"),
      finding(.telemetrySourceConflict, flight: "instructing", evidence: ["kind": "count"]),
      finding(.telemetrySourceConflict, flight: "instructing", evidence: ["kind": "time"]),
      finding(
        "block_duration",
        flight: "instructing",
        evidence: ["logged_minutes": 40, "elapsed_minutes": 60]
      ),
      finding(
        "block_duration",
        flight: "instructing",
        evidence: ["logged_minutes": 70, "elapsed_minutes": 60]
      ),
      finding(.telemetryCount, flight: "solo")
    ]

    let result = InstructionPolicy.suppress(findings, instructional: ["instructing"])

    #expect(
      result.excluded.map(\.finding.rule) == [
        .telemetryCount, .telemetrySourceConflict, "block_duration"
      ]
    )
    #expect(result.excluded.allSatisfy { $0.policy == "ignore_instruction_activity" })
    #expect(result.retained.count == 4)
  }
}

@Suite
struct `Evidence contexts` {
  private let consistent = flightSegment(startingAt: "2026-10-12T14:21:00Z", cruiseSeconds: 2_740)

  private func build(
    flights: [Flight],
    records: [FlyStoRecord] = [],
    segments: [TrackSegment] = [],
    pilot: PilotProfile = .init()
  ) throws -> [RecordID: EvidenceContext] {
    let matches = EvidenceMatcher().matchExports(records, to: flights)
    let correlation = try SegmentCorrelator().correlate(segments, with: flights)
    return try EvidenceContextBuilder(aircraft: [:], pilot: pilot, flights: flights).contexts(
      for: flights,
      records: records,
      flyStoMatches: matches,
      segments: segments,
      segmentMatches: correlation.matches
    )
  }

  @Test
  func `prefers FlySto for each value and keeps ADS-B for the rest`() throws {
    let flySto = record(takeoff: "2026-10-12T14:23:00Z", landings: nil)

    let context = try #require(
      try build(flights: [flight("A")], records: [flySto], segments: [consistent])["A"]
    )

    #expect(context.primarySource == .flySto)
    #expect(context.times[.takeoff] == utc("2026-10-12T14:23:00Z"))
    #expect(context.timeSources[.takeoff] == .flySto)
    #expect(context.times[.landing] == utc("2026-10-12T15:08:00Z"))
    #expect(context.counts[.takeoff] == 1)
    #expect(context.counts[.landing] == 1)
    #expect(context.countSources[.landing] == .adsbLol)
    #expect(context.start == utc("2026-10-12T14:10:00Z"))
  }

  @Test
  func `has no block times from ADS-B alone and falls back to the logged ones`() throws {
    let context = try #require(try build(flights: [flight("A")], segments: [consistent])["A"])

    #expect(context.primarySource == .adsbLol)
    #expect(context.times[.out] == nil)
    #expect(context.times[.takeoff] == utc("2026-10-12T14:22:00Z"))
    #expect(context.start == utc("2026-10-12T14:10:00Z"))
    #expect(context.startBasis == nil)
    #expect(context.hasPositions)
  }

  @Test
  func `leaves a count unknown when FlySto's rows disagree`() throws {
    let conflicted = record(takeoffs: nil, conflicts: [.count(.takeoff)])

    let context = try #require(
      try build(flights: [flight("A")], records: [conflicted], segments: [consistent])["A"]
    )

    #expect(context.counts[.takeoff] == nil)
    #expect(context.counts[.landing] == 1)
  }

  @Test
  func `marks instructional entries`() throws {
    var pilot = PilotProfile()
    pilot.ignoresInstructionActivity = true
    pilot.ownerPersonID = "owner"
    let instructing = flight("A", crew: FlightCrew(instructor: person("owner")))

    let context = try #require(
      try build(flights: [instructing], records: [record()], pilot: pilot)["A"]
    )

    #expect(context.isInstruction)
    #expect(throws: EvidenceError.ownerNotIdentified) {
      var unowned = pilot
      unowned.ownerPersonID = nil
      return try build(flights: [instructing], records: [record()], pilot: unowned)
    }
  }

  @Test
  func `adds ADS-B positions flown within the logged block times`() throws {
    let track = Track(registration: "N111AA", source: "adsb.lol", samples: consistent.track)
    let flights = [flight("A"), flight("B", tail: "N222BB")]
    var contexts = [RecordID: EvidenceContext]()

    try EvidenceContextBuilder(aircraft: [:], pilot: .init(), flights: flights)
      .addADSBPositions(to: &contexts, flights: flights, tracks: [track])

    let context = try #require(contexts["A"])
    #expect(contexts["B"] == nil)
    #expect(context.primarySource == .adsbLol)
    #expect(context.positionSource == .adsbLol)
    #expect(context.adsbPoints.count == consistent.track.count)
    #expect(context.times[.out] == utc("2026-10-12T14:10:00Z"))
  }

  @Test
  func `rejects positions that can't be reached from an airport anchor`() throws {
    var context = try #require(try build(flights: [flight("A")], segments: [consistent])["A"])
    // The takeoff is the anchor; a position 5 degrees away a minute later is unreachable.
    for index in context.events.indices where context.events[index].kind == .takeoff {
      context.events[index].airport = "KSQL"
    }
    let takeoff = try #require(context.events.first { $0.kind == .takeoff })
    let teleport = TrackSample(
      time: takeoff.time + 60,
      latitudeDeg: 42,
      longitudeDeg: -122,
      groundSpeedKts: 100
    )
    let nearby = TrackSample(
      time: takeoff.time + 120,
      latitudeDeg: 37.01,
      longitudeDeg: -122,
      groundSpeedKts: 100
    )
    context.points = [teleport, nearby].map { EvidencePoint(sample: $0) }

    context.sanitizePositions()

    #expect(context.points.map(\.isPositionOutlier) == [true, false])
    #expect(context.positionOutliers == 1)
  }

  @Test
  func `rejects nothing without an anchored event`() throws {
    var context = try #require(try build(flights: [flight("A")], segments: [consistent])["A"])
    context.points = [
      EvidencePoint(sample: TrackSample(time: .now, latitudeDeg: 95, longitudeDeg: 0))
    ]

    context.sanitizePositions()

    #expect(context.points[0].isPositionOutlier)
    #expect(context.positionOutliers == 0)
  }
}
