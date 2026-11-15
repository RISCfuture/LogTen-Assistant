public import FlightSources
public import Foundation
public import LogbookModel
import MeasurementKit
import MeasurementKitLocation
public import Tracks

extension EvidenceSource {
  /// The evidence source a track source's name refers to; unknown names count as adsb.lol.
  public init(trackSourceName name: String) {
    self = name == OpenSkyClient.sourceName ? .openSky : .adsbLol
  }
}

/// A track position with a verdict on whether it can be trusted.
public struct EvidencePoint: Hashable, Sendable {
  /// The sample.
  public var sample: TrackSample
  /// Whether the position is physically unreachable from the trusted observations around it,
  /// or not a valid coordinate, so it should not be drawn or measured.
  public var isPositionOutlier: Bool

  /// Creates a point.
  public init(sample: TrackSample, isPositionOutlier: Bool = false) {
    self.sample = sample
    self.isPositionOutlier = isPositionOutlier
  }
}

/// Everything known about one logbook entry from external sources: what each source observed,
/// which source each value comes from, and the track that supports it.
///
/// For each time and count, FlySto wins over the track sources. A track's block-out and
/// block-in are never used, since a position report doesn't show brakes off or on.
public struct EvidenceContext: Hashable, Sendable {
  /// The entry.
  public var flightID: RecordID

  /// The source that anchors the context: FlySto if it matched, otherwise the track source.
  public var primarySource: EvidenceSource

  /// The FlySto record and segment identifiers the context was built from.
  public var sourceIDs: [String]

  /// The track segments assigned to the entry.
  public var segments: [TrackSegment]

  /// The positions that support the entry, in time order.
  public var points: [EvidencePoint]

  /// Every ADS-B position within the entry's logged block times, in time order.
  public var adsbPoints: [EvidencePoint]

  /// The events detected in the segments, in time order.
  public var events: [TrackEvent]

  /// The best-known time of each event.
  public var times: [FlyStoTimeKind: Date]

  /// The source of each time in ``times``.
  public var timeSources: [FlyStoTimeKind: EvidenceSource]

  /// The best-known count of each event; absent when unknown or in conflict.
  public var counts: [FlyStoCountKind: UInt]

  /// The source of each count in ``counts``.
  public var countSources: [FlyStoCountKind: EvidenceSource]

  /// The start of the entry's interval: the best-known block-out, else the logged one.
  public var start: Date?

  /// The end of the entry's interval: the best-known block-in, else the logged one.
  public var end: Date?

  /// The departure airport identifier from the best source.
  public var from: String?

  /// The destination airport identifier from the best source.
  public var to: String?

  /// Links to the flight on flysto.net.
  public var urls: [URL]

  /// Distances FlySto computed.
  public var metrics: FlyStoMetrics

  /// Whether the instruction-activity policy applies to the entry.
  public var isInstruction: Bool

  /// The source of ``start``; `nil` means the logbook.
  public var startBasis: EvidenceSource?

  /// The source of ``end``; `nil` means the logbook.
  public var endBasis: EvidenceSource?

  /// The source of the positions in ``points``, if any.
  public var positionSource: EvidenceSource?

  /// How many positions ``sanitizePositions(speedBoundKnots:)`` rejected.
  public var positionOutliers = 0

  /// Whether the context has any positioned sample.
  public var hasPositions: Bool { points.contains { !$0.isPositionOutlier } }
}

extension EvidenceContext {
  /// The default speed bound for position checks, in knots.
  public static let defaultSpeedBoundKnots = 600.0

  private static let toleranceNM = 3.0
  private static let secondsPerHour = 3_600.0

  private var anchorEvent: TrackEvent? {
    events.filter {
      ($0.kind == .takeoff || $0.kind == .landing) && $0.airport != nil && $0.confidence != .low
        && $0.latitudeDeg.map(Self.isValid(latitude:)) == true
        && $0.longitudeDeg.map(Self.isValid(longitude:)) == true
    }
    .min { $0.time < $1.time }
  }

  private static func isValid(_ sample: TrackSample) -> Bool {
    isValid(latitude: sample.latitudeDeg) && isValid(longitude: sample.longitudeDeg)
  }

  private static func isValid(latitude: Double) -> Bool { (-90...90).contains(latitude) }

  private static func isValid(longitude: Double) -> Bool { (-180...180).contains(longitude) }

  /**
   Marks positions that couldn't have been reached from a trusted observation.

   The earliest takeoff or landing with a known airport anchors the track. Moving outward in
   both directions, a position is rejected if it is farther from the last accepted one than an
   aircraft at the speed bound could travel in the elapsed time, plus three nautical miles of
   slack. Without an anchor nothing is rejected, and rejected positions are marked rather than
   removed.

   - Parameter speedBoundKnots: The fastest the aircraft could plausibly travel.
   */
  public mutating func sanitizePositions(speedBoundKnots: Double = defaultSpeedBoundKnots) {
    positionOutliers = 0
    for index in points.indices where !Self.isValid(points[index].sample) {
      points[index].isPositionOutlier = true
    }
    guard let anchor = anchorEvent else { return }
    let forward = points.indices.filter { points[$0].sample.time >= anchor.time }
    let backward = points.indices.filter { points[$0].sample.time < anchor.time }.reversed()
    for indices in [forward, Array(backward)] {
      var prior = (
        time: anchor.time,
        coordinate: Coordinate(latitude: anchor.latitudeDeg!, longitude: anchor.longitudeDeg!)
      )
      for index in indices where !points[index].isPositionOutlier {
        let sample = points[index].sample
        let here = Coordinate(latitude: sample.latitudeDeg, longitude: sample.longitudeDeg)
        let elapsed = abs(sample.time.timeIntervalSince(prior.time))
        let reachable = speedBoundKnots * elapsed / Self.secondsPerHour + Self.toleranceNM
        if prior.coordinate.distance(to: here).converted(to: .nauticalMiles).value > reachable {
          points[index].isPositionOutlier = true
          positionOutliers += 1
        } else {
          prior = (sample.time, here)
        }
      }
    }
  }
}

/// Assembles an ``EvidenceContext`` for every entry that external evidence describes, a port of
/// cleanup-logten's `evidence.build_contexts` and `add_adsb_evidence`.
public struct EvidenceContextBuilder: Sendable {
  private static let blockAndFlightEvents: [FlyStoTimeKind] = [.out, .takeoff, .landing, .in]

  private let identity: AircraftIdentity
  private let instructional: Set<RecordID>

  /**
   Creates a builder.

   - Parameters:
     - aircraft: Per-aircraft settings keyed by registration.
     - pilot: The pilot's profile. When it says to ignore instruction activity, entries where
       the owner instructs or someone else is the student are marked as instruction.
     - flights: The logbook entries, used to find instructional ones.
   - Throws: ``EvidenceError/ownerNotIdentified`` if instruction activity is ignored but the
     owner isn't a person in the logbook's crew.
   */
  public init(aircraft: [String: AircraftSettings], pilot: PilotProfile, flights: [Flight]) throws {
    identity = AircraftIdentity(settings: aircraft)
    instructional =
      pilot.ignoresInstructionActivity
      ? try InstructionPolicy.instructionalFlightIDs(in: flights, owner: pilot.ownerPersonID) : []
  }

  /// The first takeoff and last landing. A track never supplies block times.
  private static func trackTimes(_ events: [TrackEvent]) -> [FlyStoTimeKind: Date] {
    var times = [FlyStoTimeKind: Date]()
    times[.takeoff] = events.first { $0.kind == .takeoff }?.time
    times[.landing] = events.last { $0.kind == .landing }?.time
    return times.compactMapValues(\.self)
  }

  private static func airport(in events: [TrackEvent], kind: TrackEvent.Kind) -> String? {
    let found = events.filter { $0.kind == kind && $0.airport != nil }
    return (kind == .takeoff ? found.first : found.last)?.airport
  }

  /**
   Builds contexts from FlySto records and track segments.

   - Parameters:
     - flights: The logbook entries.
     - records: The FlySto records.
     - flyStoMatches: How the records were matched to entries; only unique matches are used,
       and an entry with several matched records gets none of them.
     - segments: Track segments.
     - segmentMatches: How the segments were matched to entries; only single-entry matches are
       used.
   - Returns: A context for each entry that has a matched record or segment.
   */
  public func contexts(
    for flights: [Flight],
    records: [FlyStoRecord],
    flyStoMatches: [EvidenceMatch],
    segments: [TrackSegment],
    segmentMatches: [SegmentMatch]
  ) -> [RecordID: EvidenceContext] {
    let recordsByID = Dictionary(records.filter(\.isFlight).map { ($0.id, $0) }) { first, _ in first
    }
    let segmentsByID = Dictionary(segments.filter(\.isFlight).map { ($0.id, $0) }) { first, _ in
      first
    }

    var segmentsByFlight = [RecordID: [TrackSegment]]()
    for match in segmentMatches
    where [.matched, .manual].contains(match.status) && match.flightIDs.count == 1 {
      if let segment = segmentsByID[match.segmentID] {
        segmentsByFlight[match.flightIDs[0], default: []].append(segment)
      }
    }
    var recordsByFlight = [RecordID: [FlyStoRecord]]()
    for match in flyStoMatches where match.status == .matched {
      if let id = match.flightID, let record = recordsByID[match.sourceID] {
        recordsByFlight[id, default: []].append(record)
      }
    }

    var contexts = [RecordID: EvidenceContext]()
    for flight in flights {
      let segments = (segmentsByFlight[flight.id] ?? []).sorted { $0.start < $1.start }
      let matched = recordsByFlight[flight.id] ?? []
      let record = matched.count == 1 ? matched[0] : nil
      guard !segments.isEmpty || record != nil else { continue }
      contexts[flight.id] = context(for: flight, record: record, segments: segments)
    }
    return contexts
  }

  private func context(for flight: Flight, record: FlyStoRecord?, segments: [TrackSegment])
    -> EvidenceContext
  {
    let events = segments.flatMap(\.events).sorted { $0.time < $1.time }
    let trackSource = segments.first.map { EvidenceSource(trackSourceName: $0.source) } ?? .adsbLol

    var times = [FlyStoTimeKind: Date]()
    var timeSources = [FlyStoTimeKind: EvidenceSource]()
    for (kind, time) in Self.trackTimes(events) {
      times[kind] = time
      timeSources[kind] = trackSource
    }
    var counts = [FlyStoCountKind: UInt]()
    var countSources = [FlyStoCountKind: EvidenceSource]()
    if !segments.isEmpty {
      for kind in FlyStoCountKind.allCases {
        counts[kind] = UInt(events.filter { $0.kind.rawValue == kind.rawValue }.count)
        countSources[kind] = trackSource
      }
    }
    if let record {
      overlay(
        record,
        onto: &times,
        timeSources: &timeSources,
        counts: &counts,
        countSources: &countSources
      )
    }

    let points = segments.flatMap(\.track).sorted { $0.time < $1.time }.map {
      EvidencePoint(sample: $0)
    }
    var context = EvidenceContext(
      flightID: flight.id,
      primarySource: record != nil ? .flySto : trackSource,
      sourceIDs: (record.map { [$0.id] } ?? []) + segments.map(\.id),
      segments: segments,
      points: points,
      adsbPoints: [],
      events: events,
      times: times,
      timeSources: timeSources,
      counts: counts,
      countSources: countSources,
      start: times[.out] ?? flight.events.out,
      end: times[.in] ?? flight.events.in,
      from: record?.from.flatMap { $0.isEmpty ? nil : $0 }
        ?? Self.airport(in: events, kind: .takeoff),
      to: record?.to.flatMap { $0.isEmpty ? nil : $0 } ?? Self.airport(in: events, kind: .landing),
      urls: record?.urls ?? [],
      metrics: record?.metrics ?? .init(),
      isInstruction: instructional.contains(flight.id),
      startBasis: timeSources[.out],
      endBasis: timeSources[.in],
      positionSource: points.isEmpty ? nil : trackSource
    )
    context.sanitizePositions()
    return context
  }

  /// FlySto's times replace the track's, unless its clock times can't be trusted; its counts
  /// replace the track's unless repeated rows disagree, in which case the count is unknown.
  private func overlay(
    _ record: FlyStoRecord,
    onto times: inout [FlyStoTimeKind: Date],
    timeSources: inout [FlyStoTimeKind: EvidenceSource],
    counts: inout [FlyStoCountKind: UInt],
    countSources: inout [FlyStoCountKind: EvidenceSource]
  ) {
    for kind in Self.blockAndFlightEvents where record.timeIssues.isEmpty {
      if let time = record.times[kind] {
        times[kind] = time
        timeSources[kind] = .flySto
      }
    }
    for kind in FlyStoCountKind.allCases {
      if record.conflicts.contains(.count(kind)) {
        counts[kind] = nil
        countSources[kind] = nil
      } else if let count = record.counts[kind] {
        counts[kind] = count
        countSources[kind] = .flySto
      }
    }
  }

  /**
   Adds ADS-B positions flown within each entry's logged block times.

   The positions are kept as the context's ``EvidenceContext/adsbPoints``, and become its
   ``EvidenceContext/points`` where no other source has positions. An entry without a context
   gets one that rests on the logbook's own times.

   - Parameters:
     - contexts: The contexts to extend.
     - flights: The logbook entries.
     - tracks: ADS-B tracks.
   */
  public func addADSBPositions(
    to contexts: inout [RecordID: EvidenceContext],
    flights: [Flight],
    tracks: [Track]
  ) {
    for flight in flights {
      guard let out = flight.events.out, let `in` = flight.events.in, `in` > out else { continue }
      let flown = tracks.filter { identity.isSame($0.registration, flight.aircraft?.registration) }
      let samples = flown.flatMap(\.samples).filter { $0.time >= out && $0.time <= `in` }
      let points = samples.sorted { $0.time < $1.time }.map { EvidencePoint(sample: $0) }
      guard !points.isEmpty else { continue }
      if var context = contexts[flight.id] {
        context.adsbPoints = points
        if !context.hasPositions {
          context.points = points
          context.positionSource = .adsbLol
          context.sanitizePositions()
        }
        contexts[flight.id] = context
      } else {
        contexts[flight.id] = adsbOnlyContext(for: flight, out: out, in: `in`, points: points)
      }
    }
  }

  private func adsbOnlyContext(for flight: Flight, out: Date, in end: Date, points: [EvidencePoint])
    -> EvidenceContext
  {
    var context = EvidenceContext(
      flightID: flight.id,
      primarySource: .adsbLol,
      sourceIDs: [],
      segments: [],
      points: points,
      adsbPoints: points,
      events: [],
      times: Dictionary(
        uniqueKeysWithValues: [
          (FlyStoTimeKind.out, out), (.in, end)
        ]
          + [(FlyStoTimeKind.takeoff, flight.events.off), (.landing, flight.events.on)].compactMap {
            kind,
            time in time.map { (kind, $0) }
          }
      ),
      timeSources: [:],
      counts: [:],
      countSources: [:],
      start: out,
      end: end,
      urls: [],
      metrics: .init(),
      isInstruction: instructional.contains(flight.id),
      positionSource: .adsbLol
    )
    context.sanitizePositions()
    return context
  }
}
