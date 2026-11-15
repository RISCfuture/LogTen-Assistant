import Audit
import FlightSources
import Foundation
import LogbookModel
import Testing
import Tracks

@Suite
struct `Night audit` {
  private static let home = (latitude: 37.62, longitude: -122.38)

  /// A two-hour out-and-back near San Francisco starting at `start`.
  private func flown(from start: String, hours: Double = 2) -> (Date, [TrackSample]) {
    let begin = utc(start)
    let there = offset(Self.home, east: 15, north: 5)
    let track = samples(
      through: [
        Keyframe(seconds: 0, latitude: Self.home.latitude, longitude: Self.home.longitude),
        Keyframe(seconds: hours * 1_800, latitude: there.latitude, longitude: there.longitude),
        Keyframe(
          seconds: hours * 3_600,
          latitude: Self.home.latitude,
          longitude: Self.home.longitude
        )
      ],
      from: begin,
      step: 30
    )
    return (begin, track)
  }

  private func entry(
    from start: Date,
    hours: Double = 2,
    night: UInt,
    counts: FlightCounts = .init(),
    customValues: [LogTenFieldKey: FieldValue] = [:]
  ) -> Flight {
    var entry = flight("A")
    entry.events = FlightEvents(
      out: start,
      off: nil,
      on: nil,
      in: start.addingTimeInterval(hours * 3_600)
    )
    entry.times = FlightTimes(total: UInt(hours * 60), night: night)
    entry.counts = counts
    entry.customValues = customValues
    return entry
  }

  private func audit(_ entry: Flight, _ context: EvidenceContext, mapping: FieldMapping = .init())
    -> NightAuditResult
  {
    NightAudit(mapping: mapping).run(on: [entry], contexts: ["A": context])
  }

  @Test
  func `reports night time logged on a flight the track shows in daylight`() throws {
    let (start, track) = flown(from: "2024-06-12T18:00:00Z")
    var context = try baseContext()
    context.fly(track)

    let result = audit(entry(from: start, night: 60), context)

    let finding = try #require(result.findings.first)
    #expect(finding.rule == .telemetryNightTime)
    #expect(finding.evidence["max"] == .double(0))
    let diagnostics = try #require(result.diagnostics[finding.id])
    #expect(diagnostics.track.maximumMinutes == 0)
    #expect(diagnostics.track.estimateMinutes == 0)
    #expect(diagnostics.usesLoggedBlockTimes)
    #expect(result.followUps[finding.id]?.notes.isEmpty == false)
  }

  @Test
  func `accepts night time within the bounds`() throws {
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    var context = try baseContext()
    context.fly(track)

    #expect(audit(entry(from: start, night: 120), context).findings.isEmpty)
    #expect(
      audit(entry(from: start, night: 0), context).findings.map(\.rule) == [.telemetryNightTime]
    )
  }

  @Test
  func `doesn't call missing night credit an error on a partial or instructional entry`() throws {
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    var context = try baseContext()
    context.fly(track)
    var partial = entry(from: start, night: 0)
    partial.times.total = 30
    var instruction = context
    instruction.isInstruction = true

    #expect(audit(partial, context).findings.isEmpty)
    #expect(audit(entry(from: start, night: 0), instruction).findings.isEmpty)
  }

  @Test
  func `can't judge an interval the track doesn't cover`() throws {
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    var context = try baseContext()
    context.fly(Array(track.prefix(10)))
    context.end = start.addingTimeInterval(7_200)

    #expect(audit(entry(from: start, night: 0), context).findings.isEmpty)
  }

  // MARK: Events

  private func nightEventContext(start: Date, track: [TrackSample]) throws -> EvidenceContext {
    var context = try baseContext()
    context.fly(track)
    let takeoff = start.addingTimeInterval(600)
    let landing = start.addingTimeInterval(6_600)
    let home = Self.home
    context.events = [
      event(.takeoff, at: takeoff, home.latitude, home.longitude),
      event(.landing, at: landing, home.latitude, home.longitude),
      event(.fullStop, at: landing.addingTimeInterval(60), home.latitude, home.longitude)
    ]
    context.counts = [.takeoff: 1, .landing: 1]
    context.countSources = [.takeoff: .flySto, .landing: .flySto]
    return context
  }

  @Test
  func `compares logged night takeoffs, landings and full stops with the events`() throws {
    var mapping = FieldMapping()
    let fullStops = LogTenFieldKey.custom(.flightLanding, 5)
    try mapping.assign(fullStops, to: .nightFullStops)
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    let context = try nightEventContext(start: start, track: track)
    let logged = entry(
      from: start,
      night: 120,
      counts: FlightCounts(dayTakeoffs: 1, dayLandings: 1),
      customValues: [fullStops: .integer(0)]
    )

    let result = audit(logged, context, mapping: mapping)

    let byField = Dictionary(
      uniqueKeysWithValues: result.findings.map { ($0.evidence["field"]?.stringValue ?? "", $0) }
    )
    #expect(
      Set(byField.keys) == [
        "daytakeoffs", "nighttakeoffs", "daylandings", "nightlandings", "customlanding5"
      ]
    )
    #expect(byField["nighttakeoffs"]?.evidence["observed"] == .integer(1))
    #expect(byField["daytakeoffs"]?.evidence["observed"] == .integer(0))
    #expect(byField["customlanding5"]?.rule == .telemetryNightFullStops)
    #expect(byField["customlanding5"]?.evidence["window"] == "sunset + 1 hour to sunrise - 1 hour")
  }

  @Test
  func `agrees when the logged counts match the events`() throws {
    var mapping = FieldMapping()
    let fullStops = LogTenFieldKey.custom(.flightLanding, 5)
    try mapping.assign(fullStops, to: .nightFullStops)
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    let context = try nightEventContext(start: start, track: track)
    let logged = entry(
      from: start,
      night: 120,
      counts: FlightCounts(nightTakeoffs: 1, nightLandings: 1),
      customValues: [fullStops: .integer(1)]
    )

    #expect(audit(logged, context, mapping: mapping).findings.isEmpty)
  }

  @Test
  func `ignores events when FlySto's count disagrees with the track`() throws {
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    var context = try nightEventContext(start: start, track: track)
    context.counts[.landing] = 2

    let result = audit(entry(from: start, night: 120, counts: .init(dayLandings: 1)), context)

    #expect(
      !result.findings.contains {
        $0.rule == .telemetryNightEvent
          && $0.evidence["field"] == "nightlandings"
      }
    )
  }

  @Test
  func `ignores events when the track has a gap`() throws {
    let (start, track) = flown(from: "2024-12-22T08:00:00Z")
    var context = try nightEventContext(start: start, track: track)
    context.fly(track.enumerated().filter { !(50..<60).contains($0.offset) }.map(\.element))

    let result = audit(entry(from: start, night: 120, counts: .init(dayTakeoffs: 1)), context)

    #expect(result.findings.isEmpty)
  }
}

@Suite
struct `Track night estimate` {
  @Test
  func `bounds the estimate by what the samples can show`() throws {
    // Night over the whole interval, but one stretch has no samples.
    let start = utc("2024-12-22T08:00:00Z")
    let all = samples(
      through: [
        Keyframe(seconds: 0, latitude: 37.6, longitude: -122.4),
        Keyframe(seconds: 3_600, latitude: 37.7, longitude: -122.3)
      ],
      from: start,
      step: 30
    )
    let withGap = all.filter { !(1_200..<2_400).contains($0.time.timeIntervalSince(start)) }

    let estimate = try #require(
      TrackNightEstimate(samples: withGap, from: start, to: start.addingTimeInterval(3_600))
    )

    #expect(abs(estimate.minimumMinutes - 40) < 1)
    #expect(abs(estimate.maximumMinutes - 60) < 1)
    #expect(abs(estimate.missingMinutes - 20) < 1)

    // A wider gap lets the same hole be interpolated instead of left unknown.
    let widened = try #require(
      TrackNightEstimate(
        samples: withGap,
        from: start,
        to: start.addingTimeInterval(3_600),
        gapSeconds: 1_300
      )
    )
    #expect(abs(widened.minimumMinutes - 60) < 1)
    #expect(widened.missingMinutes == 0)
  }

  @Test
  func `has no estimate for an empty interval`() {
    let start = utc("2024-12-22T08:00:00Z")

    #expect(TrackNightEstimate(samples: [], from: start, to: start) == nil)
  }
}

@Suite
struct `Endpoint night comparison` {
  private let sanFrancisco = (latitudeDeg: 37.62, longitudeDeg: -122.38)
  private let sanDiego = (latitudeDeg: 32.73, longitudeDeg: -117.19)

  private func comparison(
    _ start: String,
    hours: Double = 1,
    from origin: (latitudeDeg: Double, longitudeDeg: Double)? = nil,
    to destination: (latitudeDeg: Double, longitudeDeg: Double)? = nil
  ) -> EndpointNightComparison? {
    EndpointNightComparison(
      from: utc(start),
      to: utc(start).addingTimeInterval(hours * 3_600),
      origin: origin ?? sanFrancisco,
      destination: destination ?? sanDiego
    )
  }

  @Test
  func `counts every minute of a night flight and none of a day flight`() throws {
    let night = try #require(comparison("2024-12-22T08:00:00Z"))
    let day = try #require(comparison("2024-06-12T19:00:00Z"))

    #expect(night.estimateMinutes == 60)
    #expect(night.samplingMinimumMinutes == 60)
    #expect(night.intervalMinutes == 60)
    #expect(day.samplingMaximumMinutes == 0)
  }

  @Test
  func `brackets the estimate by the chunk convention across sunset`() throws {
    let dusk = try #require(comparison("2024-06-13T03:30:00Z", hours: 2))

    #expect(dusk.startSampleMinutes <= dusk.estimateMinutes)
    #expect(dusk.estimateMinutes <= dusk.endSampleMinutes)
    #expect(dusk.samplingMinimumMinutes < dusk.samplingMaximumMinutes)
  }

  @Test
  func `has no comparison for an empty interval or impossible endpoints`() {
    let antipode = (latitudeDeg: -37.62, longitudeDeg: 57.62)

    #expect(comparison("2024-12-22T08:00:00Z", hours: 0) == nil)
    #expect(comparison("2024-12-22T08:00:00Z", to: antipode) == nil)
    #expect(comparison("2024-12-22T08:00:00Z", to: (latitudeDeg: 95, longitudeDeg: 0)) == nil)
  }
}
