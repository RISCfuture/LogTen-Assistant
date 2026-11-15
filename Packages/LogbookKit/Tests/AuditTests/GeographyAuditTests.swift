import Audit
import FlightSources
import Foundation
import LogbookModel
import References
import Testing
import Tracks

private struct FixedResolver: TimeZoneResolving {
  // swiftlint:disable:next async_without_await
  func timeZoneIdentifier(latitudeDeg _: Double, longitudeDeg _: Double) async throws -> String? {
    "America/Los_Angeles"
  }
}

@Suite
struct `Geography audit` {
  // Runway midpoints of KSQL and KSFO in the synthetic reference data.
  private static let sanCarlos = (latitude: 37.5124, longitude: -122.2518)
  private static let sanFrancisco = (latitude: 37.6197, longitude: -122.375)
  private static let start = utc("2026-10-12T14:10:00Z")

  private var mapping: FieldMapping {
    var mapping = FieldMapping()
    try? mapping.assign(.custom(.flightTime, 1), to: .atpCrossCountry)
    return mapping
  }

  private func index() -> AirportIndex {
    AirportIndex(
      effectiveDate: utc("2026-10-01T00:00:00Z"),
      airports: [
        AirportReference(
          locationID: "SQL",
          ICAOID: "KSQL",
          name: "San Carlos",
          latitudeDeg: 37.5119,
          longitudeDeg: -122.2495
        ),
        AirportReference(
          locationID: "SFO",
          ICAOID: "KSFO",
          name: "San Francisco Intl",
          latitudeDeg: 37.6188,
          longitudeDeg: -122.375
        )
      ],
      runwayEnds: [
        RunwayEndReference(
          airportLocationID: "SQL",
          runwayID: "12/30",
          identifier: "12",
          latitudeDeg: 37.51525,
          longitudeDeg: -122.25362
        ),
        RunwayEndReference(
          airportLocationID: "SQL",
          runwayID: "12/30",
          identifier: "30",
          latitudeDeg: 37.50955,
          longitudeDeg: -122.2461
        ),
        RunwayEndReference(
          airportLocationID: "SFO",
          runwayID: "10L/28R",
          identifier: "10L",
          latitudeDeg: 37.6263,
          longitudeDeg: -122.393
        ),
        RunwayEndReference(
          airportLocationID: "SFO",
          runwayID: "10L/28R",
          identifier: "28R",
          latitudeDeg: 37.6131,
          longitudeDeg: -122.3569
        )
      ]
    )
  }

  /// A flight of two hours from one airport to another that the track covers completely.
  private func scenario(
    from: String = "SQL",
    to: String = "SFO",
    reaching far: (east: Double, north: Double)? = nil,
    options: GeographyAuditOptions = .init(),
    configure: (inout Flight, inout EvidenceContext) -> Void = { _, _ in }
  ) async throws -> GeographyAuditResult {
    let origin = Self.sanCarlos
    let destination = Self.sanFrancisco
    let middle = far.map { offset(origin, east: $0.east, north: $0.north) } ?? origin
    let takeoff = Self.start.addingTimeInterval(600)
    let landing = Self.start.addingTimeInterval(6_600)
    var context = try baseContext()
    context.fly(
      samples(
        through: [
          Keyframe(seconds: 0, latitude: origin.latitude, longitude: origin.longitude),
          Keyframe(seconds: 3_600, latitude: middle.latitude, longitude: middle.longitude),
          Keyframe(seconds: 7_200, latitude: destination.latitude, longitude: destination.longitude)
        ],
        from: Self.start,
        step: 60
      )
    )
    context.events = [
      event(.takeoff, at: takeoff, origin.latitude, origin.longitude),
      event(.landing, at: landing, destination.latitude, destination.longitude)
    ]
    context.times = [.takeoff: takeoff, .landing: landing]
    context.timeSources = [.takeoff: .adsbLol, .landing: .adsbLol]
    var logged = flight("A", from: from, to: to)
    logged.times = FlightTimes(total: 100)
    configure(&logged, &context)
    let timeZones = AirportTimeZones(resolver: FixedResolver())
    return await GeographyAudit(
      index: index(),
      mapping: mapping,
      options: options,
      timeZones: timeZones
    ).run(on: [logged], contexts: ["A": context])
  }

  @Test
  func `agrees with a route that matches the runways`() async throws {
    let result = try await scenario()

    #expect(result.findings.isEmpty)
  }

  @Test
  func `reports an arrival at a different airport than logged`() async throws {
    let result = try await scenario(to: "SQL")

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryAirport)
    #expect(finding.evidence["field"] == "to_place")
    #expect(finding.evidence["observed"] == "KSFO")
  }

  @Test
  func `can't name an airport when the track starts mid-flight`() async throws {
    let result = try await scenario(to: "SQL") { _, context in
      context.segments[0].isIncompleteAtEnd = true
    }

    #expect(result.findings.isEmpty)
  }

  @Test
  func `reports a landing at an airport other than the route's endpoints`() async throws {
    let result = try await scenario(from: "SQL", to: "SQL") { _, context in
      let middleStop = Self.start.addingTimeInterval(3_000)
      let sanFrancisco = Self.sanFrancisco
      context.events = [
        event(
          .takeoff,
          at: Self.start.addingTimeInterval(600),
          Self.sanCarlos.latitude,
          Self.sanCarlos.longitude
        ),
        event(.landing, at: middleStop, sanFrancisco.latitude, sanFrancisco.longitude),
        event(
          .takeoff,
          at: middleStop.addingTimeInterval(600),
          sanFrancisco.latitude,
          sanFrancisco.longitude
        ),
        event(
          .landing,
          at: Self.start.addingTimeInterval(6_600),
          Self.sanCarlos.latitude,
          Self.sanCarlos.longitude
        )
      ]
    }

    let finding = try #require(result.findings.first { $0.rule == .telemetryIntermediateStop })
    #expect(finding.evidence["observed"]?["airport"] == "KSFO")
    #expect(finding.evidence["observed"]?["mentioned_in_remarks"] == false)
  }

  @Test
  func `notes that remarks mention an intermediate stop`() async throws {
    let result = try await scenario(from: "SQL", to: "SQL") { logged, context in
      logged.remarks = "Touch and go then lunch at SFO"
      let middleStop = Self.start.addingTimeInterval(3_000)
      context.events = [
        event(
          .takeoff,
          at: Self.start.addingTimeInterval(600),
          Self.sanCarlos.latitude,
          Self.sanCarlos.longitude
        ),
        event(.landing, at: middleStop, Self.sanFrancisco.latitude, Self.sanFrancisco.longitude),
        event(
          .landing,
          at: Self.start.addingTimeInterval(6_600),
          Self.sanCarlos.latitude,
          Self.sanCarlos.longitude
        )
      ]
    }

    let finding = try #require(result.findings.first { $0.rule == .telemetryIntermediateStop })
    #expect(finding.evidence["observed"]?["mentioned_in_remarks"] == true)
  }

  @Test
  func `reports an entry date that matches neither the UTC nor the local departure date`()
    async throws
  {
    let mismatched = try await scenario { logged, _ in
      logged.date = utc("2026-10-10T00:00:00Z")
    }
    // 14:10Z is 07:10 PDT on the same day, so both calendars agree with the entry.
    let agreeing = try await scenario()
    // 03:10Z on the 13th is the evening of the 12th in California.
    let local = try await scenario { _, context in
      context.start = utc("2026-10-13T03:10:00Z")
      context.times[.out] = utc("2026-10-13T03:10:00Z")
      context.times[.takeoff] = utc("2026-10-13T03:20:00Z")
    }

    #expect(mismatched.findings.map(\.rule) == [.telemetryFlightDate])
    #expect(agreeing.findings.isEmpty)
    #expect(local.findings.isEmpty)
  }

  @Test
  func `compares the logged distance only once its unit is verified`() async throws {
    let configure: (inout Flight, inout EvidenceContext) -> Void = { logged, _ in
      logged.distanceNM = 500
    }

    let unverified = try await scenario(configure: configure)
    let verified = try await scenario(
      options: GeographyAuditOptions(isDistanceUnitNauticalMiles: true),
      configure: configure
    )

    #expect(unverified.findings.isEmpty)
    #expect(verified.findings.map(\.rule) == [.telemetryDistance])
  }

  @Test
  func `accepts a distance near the direct distance`() async throws {
    let result = try await scenario(
      options: GeographyAuditOptions(isDistanceUnitNauticalMiles: true)
    ) {
      logged,
      _ in logged.distanceNM = 9
    }

    #expect(result.findings.isEmpty)
  }

  // MARK: ATP cross-country

  @Test
  func `reports an ATP cross-country field of zero when the aircraft went beyond 50 NM`()
    async throws
  {
    let result = try await scenario(reaching: (east: 0, north: 70)) { logged, _ in
      logged.times.total = 120
      logged.customValues = [.custom(.flightTime, 1): .integer(0)]
    }

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryATPCrossCountryCandidate)
    #expect(finding.evidence["field"] == "customtime1")
  }

  @Test
  func `leaves an ATP cross-country field of zero alone on a partial-credit entry`() async throws {
    let result = try await scenario(reaching: (east: 0, north: 70)) { logged, _ in
      logged.times.total = 30
      logged.customValues = [.custom(.flightTime, 1): .integer(0)]
    }

    #expect(result.findings.isEmpty)
  }

  @Test
  func `reports ATP cross-country time on a complete track that stayed within 50 NM`() async throws
  {
    let result = try await scenario(reaching: (east: 5, north: 5)) { logged, _ in
      logged.times.total = 120
      logged.customValues = [.custom(.flightTime, 1): .integer(60)]
    }

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryATPCrossCountryIneligible)
    #expect(finding.evidence["observed"]?["conservative_upper_bound_nm"] != nil)
  }

  @Test
  func `can't rule out ATP cross-country time when samples are far apart`() async throws {
    let result = try await scenario(reaching: (east: 5, north: 5)) { logged, context in
      logged.times.total = 120
      logged.customValues = [.custom(.flightTime, 1): .integer(60)]
      context.fly(
        context.points.map(\.sample).enumerated().filter { $0.offset.isMultiple(of: 5) }.map(
          \.element
        )
      )
    }

    #expect(result.findings.isEmpty)
  }
}
