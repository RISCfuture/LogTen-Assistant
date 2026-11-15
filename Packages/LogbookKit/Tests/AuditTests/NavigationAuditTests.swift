import Audit
import Foundation
import LogbookModel
import References
import Testing
import Tracks

private struct StubLookup: ApproachLookup {
  var approaches: [PublishedApproach]

  // swiftlint:disable:next async_without_await
  func approaches(at airportIdentifier: String) async -> [PublishedApproach] {
    approaches.filter { $0.airportIdentifier == airportIdentifier }
  }
}

@Suite
struct `Navigation audit` {
  private static let start = utc("2026-10-12T14:10:00Z")
  private static let threshold = (latitude: 37.6131, longitude: -122.3569)

  private var index: AirportIndex {
    AirportIndex(
      effectiveDate: utc("2026-10-01T00:00:00Z"),
      airports: [
        AirportReference(
          locationID: "SFO",
          ICAOID: "KSFO",
          name: "San Francisco Intl",
          latitudeDeg: 37.6188,
          longitudeDeg: -122.375
        )
      ]
    )
  }

  /// ILS RWY 28R, flown from the east.
  private var ils: PublishedApproach {
    let intermediate = offset(Self.threshold, east: 5.5, north: 0.2)
    let final = offset(Self.threshold, east: 3.2, north: 0.1)
    return PublishedApproach(
      airportIdentifier: "KSFO",
      identifier: "I28R",
      family: .ils,
      typeName: "ILS",
      runway: "28R",
      fixes: [
        ApproachFix(
          name: "IF",
          latitudeDeg: intermediate.latitude,
          longitudeDeg: intermediate.longitude,
          isFinalApproachFix: false
        ),
        ApproachFix(
          name: "FAF",
          latitudeDeg: final.latitude,
          longitudeDeg: final.longitude,
          isFinalApproachFix: true
        ),
        ApproachFix(
          name: "RW28R",
          latitudeDeg: Self.threshold.latitude,
          longitudeDeg: Self.threshold.longitude,
          isFinalApproachFix: false
        )
      ]
    )
  }

  private var sanFrancisco: Place {
    Place(id: "place-SFO", identifier: "SFO", ICAO: "KSFO")
  }

  /// An aircraft that flies the ILS and lands on 28R.
  private func approachContext() throws -> EvidenceContext {
    let intermediate = offset(Self.threshold, east: 5.5, north: 0.2)
    let final = offset(Self.threshold, east: 3.2, north: 0.1)
    var context = try baseContext()
    context.fly(
      samples(
        through: [
          Keyframe(
            seconds: 0,
            latitude: intermediate.latitude - 0.1,
            longitude: intermediate.longitude + 0.1
          ),
          Keyframe(seconds: 60, latitude: intermediate.latitude, longitude: intermediate.longitude),
          Keyframe(seconds: 160, latitude: final.latitude, longitude: final.longitude),
          Keyframe(
            seconds: 260,
            latitude: Self.threshold.latitude,
            longitude: Self.threshold.longitude
          )
        ],
        from: Self.start,
        step: 5
      )
    )
    context.events = [
      event(
        .landing,
        at: Self.start.addingTimeInterval(260),
        Self.threshold.latitude,
        Self.threshold.longitude
      )
    ]
    return context
  }

  private func logged(_ type: ApproachType, runway: String = "28R") -> Flight {
    var entry = flight("A")
    entry.approaches = [
      Approach(id: "approach", place: sanFrancisco, type: type, runway: runway, count: 1)
    ]
    return entry
  }

  private func audit(_ entry: Flight, _ context: EvidenceContext, approaches: [PublishedApproach])
    async -> NavigationAuditResult
  {
    await NavigationAudit(index: index, lookup: StubLookup(approaches: approaches))
      .run(on: [entry], contexts: ["A": context])
  }

  @Test
  func `corroborates a logged approach the track flew`() async throws {
    let result = await audit(logged(.ILS), try approachContext(), approaches: [ils])

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryApproachCorroboration)
    let episode = try #require(finding.evidence["observed"]?.arrayValue?.first)
    #expect(episode["approach"] == "ILS RWY 28R")
    #expect(episode["fixes_passed"]?.arrayValue?.count == 3)
    #expect(finding.evidence["agreements"]?.arrayValue?.count == 3)
  }

  @Test
  func `reports detail that contradicts the approach the track flew`() async throws {
    let result = await audit(logged(.LPV, runway: "28L"), try approachContext(), approaches: [ils])

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryApproachDetail)
    let fields = finding.evidence["contradictions"]?.arrayValue?.compactMap {
      $0["field"]?.stringValue
    }
    #expect(Set(fields ?? []) == ["type", "runway"])
  }

  @Test
  func `names only what equally good procedures agree on`() async throws {
    var rnav = ils
    rnav.identifier = "R28R"
    rnav.family = .rnav
    rnav.typeName = "RNAV"

    let result = await audit(logged(.ILS), try approachContext(), approaches: [ils, rnav])

    let episode = try #require(result.findings.first?.evidence["observed"]?.arrayValue?.first)
    #expect(episode["approach"] == .null)
    #expect(episode["runway"] == "28R")
    #expect(episode["type"] == .null)
    #expect(episode["candidates"]?.arrayValue?.count == 2)
  }

  @Test
  func `can't tell the approach when the track missed the fixes`() async throws {
    var context = try approachContext()
    context.fly(
      context.points.map(\.sample).map {
        var moved = $0
        moved.latitudeDeg += 0.1
        return moved
      }
    )

    let result = await audit(logged(.ILS), context, approaches: [ils])

    #expect(result.findings.map(\.rule) == [.telemetryNavigationCoverage])
  }

  @Test
  func `skips entries flown as instruction`() async throws {
    var context = try approachContext()
    context.isInstruction = true

    #expect(await audit(logged(.ILS), context, approaches: [ils]).findings.isEmpty)
  }

  // MARK: Holds

  /// A racetrack of five straight legs flown at 90 knots, one minute each, turning right.
  private func racetrack() -> [TrackSample] {
    let origin = (latitude: 37.5, longitude: -122.0)
    let legNM = 1.5
    let radiusNM = 0.5
    let turnSteps = 12
    let stepSeconds = 5.0
    var keyframes = [Keyframe]()
    var seconds = 0.0
    func pass(east: Double, north: Double) {
      let position = offset(origin, east: east, north: north)
      keyframes.append(
        Keyframe(
          seconds: seconds,
          latitude: position.latitude,
          longitude: position.longitude,
          altitudeFt: 5_000,
          knots: 90
        )
      )
    }
    pass(east: 0, north: 0)
    seconds = 60
    pass(east: legNM, north: 0)
    for turn in 0..<4 {
      let atEastEnd = turn.isMultiple(of: 2)
      let centerEast = atEastEnd ? legNM : 0
      let startAngle = atEastEnd ? Double.pi / 2 : -Double.pi / 2
      for step in 1...turnSteps {
        let angle = startAngle - Double(step) * .pi / Double(turnSteps)
        seconds += stepSeconds
        pass(
          east: centerEast + radiusNM * cos(angle),
          north: -radiusNM + radiusNM * sin(angle)
        )
      }
      seconds += 60
      pass(east: atEastEnd ? 0 : legNM, north: atEastEnd ? -2 * radiusNM : 0)
    }
    return samples(through: keyframes, from: Self.start, step: stepSeconds)
  }

  private func holdingContext() throws -> EvidenceContext {
    var context = try baseContext()
    context.fly(racetrack())
    return context
  }

  private func instrumentFlight(holds: UInt = 0) -> Flight {
    var entry = flight("A")
    entry.times = FlightTimes(actualInstrument: 30)
    entry.counts = FlightCounts(holds: holds)
    return entry
  }

  @Test
  func `finds a racetrack in logged instrument conditions`() async throws {
    let result = await NavigationAudit().run(
      on: [instrumentFlight(holds: 1)],
      contexts: ["A": try holdingContext()]
    )

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryHoldCandidates)
    let hold = try #require(finding.evidence["observed"]?.arrayValue?.first)
    #expect(hold["reciprocal_legs"] == 5)
    #expect(hold["turn_direction"] == "right")
    #expect(hold["confirmed_hold"] == false)
  }

  @Test
  func `looks for holds only in logged instrument conditions`() async throws {
    let result = await NavigationAudit().run(
      on: [flight("A")],
      contexts: ["A": try holdingContext()]
    )

    #expect(result.findings.isEmpty)
  }

  @Test
  func `reports logged holds the track can't show`() async throws {
    var context = try baseContext()
    context.fly(
      samples(
        through: [
          Keyframe(seconds: 0, latitude: 37.5, longitude: -122),
          Keyframe(seconds: 600, latitude: 37.6, longitude: -122)
        ],
        from: Self.start,
        step: 5
      )
    )

    let result = await NavigationAudit().run(
      on: [instrumentFlight(holds: 2)],
      contexts: ["A": context]
    )

    #expect(result.findings.map(\.rule) == [.telemetryNavigationCoverage])
  }
}
