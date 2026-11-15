public import Foundation
public import LogbookModel

/// One continuous recording of an aircraft, from the first sample after a break to the last
/// before the next, with the events detected in it.
public struct TrackSegment: Identifiable, Hashable, Codable, Sendable {
  /// The most samples kept in ``track`` for display.
  public static let maximumDisplaySamples = 300

  /// A content-addressed identifier derived from the aircraft and the segment's bounds.
  public let id: String

  /// The aircraft's registration.
  public var registration: String

  /// The name of the source the samples came from, such as “adsb.lol”.
  public var source: String

  /// The time of the first sample.
  public var start: Date

  /// The time of the last sample.
  public var end: Date

  /// The events detected in the segment, in time order.
  public var events: [TrackEvent]

  /// An evenly thinned subset of the positioned samples, for display.
  public var track: [TrackSample]

  /// The number of samples in the segment.
  public var sampleCount: Int

  /// Whether any sample was at or above the airborne speed.
  public var hasAirborneEvidence: Bool

  /// Whether the speed was known and stayed at ground speeds throughout.
  public var hasGroundEvidence: Bool

  /// Whether recording began after the aircraft was already airborne.
  public var isIncompleteAtStart: Bool

  /// Whether recording ended before the aircraft landed.
  public var isIncompleteAtEnd: Bool

  /// The segment's time span.
  public var interval: DateInterval { DateInterval(start: start, end: end) }

  /// Whether the segment is a complete flight, a ground session or neither.
  public var kind: Kind {
    if isIncompleteAtStart || isIncompleteAtEnd { return .incomplete }
    let boundaries = events.filter { $0.kind == .takeoff || $0.kind == .landing }
      .sorted { $0.time < $1.time }
    if let first = boundaries.first, let last = boundaries.last, first.kind == .takeoff,
      last.kind == .landing, first.time < last.time
    {
      return .flight
    }
    if !boundaries.isEmpty || hasAirborneEvidence { return .incomplete }
    return hasGroundEvidence ? .nonflight : .incomplete
  }

  /// Whether ``kind`` is ``Kind/flight``.
  public var isFlight: Bool { kind == .flight }

  /// Creates a segment from its samples, detecting its events.
  public init(
    registration: String,
    source: String = "",
    samples: [TrackSample],
    settings: TrackDetectionSettings
  ) {
    precondition(!samples.isEmpty, "A segment needs at least one sample")
    let track = Track(registration: registration, source: "", samples: samples)
    let start = track.samples[0].time
    let end = track.samples[track.samples.count - 1].time
    self.id = Self.identifier(registration: registration, start: start, end: end)
    self.registration = registration
    self.source = source
    self.start = start
    self.end = end
    self.events = track.detectEvents(settings: settings)
    self.track = Self.thinned(track.samples)
    self.sampleCount = track.samples.count
    self.hasAirborneEvidence = track.samples.contains {
      max($0.groundSpeedKts ?? 0, 0) >= settings.airborneKts && $0.isOnGround != true
    }
    self.hasGroundEvidence = Self.isEntirelyGround(track.samples, settings: settings)
    self.isIncompleteAtStart = false
    self.isIncompleteAtEnd = false
  }

  private static func identifier(registration: String, start: Date, end: Date) -> String {
    let digest = CanonicalJSON.sha256(
      of: [
        .string(registration), .double(start.timeIntervalSince1970),
        .double(end.timeIntervalSince1970)
      ]
    )
    return String(digest.prefix(20))
  }

  private static func thinned(_ samples: [TrackSample]) -> [TrackSample] {
    let step = max(1, (samples.count + maximumDisplaySamples - 1) / maximumDisplaySamples)
    return stride(from: 0, to: samples.count, by: step).map { samples[$0] }
  }

  private static func isEntirelyGround(
    _ samples: [TrackSample],
    settings: TrackDetectionSettings
  ) -> Bool {
    samples.contains { $0.groundSpeedKts != nil }
      && samples.allSatisfy { ($0.groundSpeedKts ?? 0) <= settings.groundKts }
  }

  /// What the segment shows about flight activity.
  public enum Kind: String, CaseIterable, Codable, Sendable {
    /// An observed takeoff followed by an observed landing.
    case flight
    /// Recorded entirely on the ground.
    case nonflight
    /// Missing a takeoff or landing, so it can't be treated as a complete flight.
    case incomplete
  }
}

/// The result of splitting tracks into segments and classifying them.
public struct TrackSegmentation: Hashable, Sendable {
  /// Segments with an observed takeoff and landing, in time order per aircraft.
  public var flights: [TrackSegment]

  /// Segments recorded entirely on the ground.
  public var nonflight: [TrackSegment]

  /// Segments missing a takeoff or landing.
  public var incomplete: [TrackSegment]
}

/// Splits tracks into segments and classifies them, a port of cleanup-logten's
/// `build_segments`, `classify_segment` and `partition_segments`.
public struct TrackSegmenter: Sendable {
  private let settings: TrackDetectionSettings
  private let aircraft: [String: AircraftSettings]

  /**
   Creates a segmenter.

   - Parameters:
     - settings: The global detection thresholds.
     - aircraft: Per-aircraft settings keyed by registration; an aircraft's
       `AircraftSettings.trackDetection` overrides replace the global thresholds.
   */
  public init(
    settings: TrackDetectionSettings = .init(),
    aircraft: [String: AircraftSettings] = [:]
  ) {
    self.settings = settings
    self.aircraft = aircraft
  }

  /**
   Segments and classifies every aircraft's tracks.

   Tracks for the same registration from the same source are merged first. A segment ends at a gap longer than the
   aircraft's gap threshold, or when the aircraft sits still for ten minutes after flying.

   - Parameter tracks: The tracks to segment, from any sources.
   - Returns: The segments, partitioned by kind.
   */
  public func segment(_ tracks: [Track]) -> TrackSegmentation {
    let groups = Dictionary(grouping: tracks) {
      Origin(registration: $0.registration, source: $0.source)
    }
    let segments = groups.keys.sorted().flatMap { origin in
      let samples = groups[origin, default: []].flatMap(\.samples).sorted { $0.time < $1.time }
      return segments(of: samples, origin: origin)
    }
    return TrackSegmentation(
      flights: segments.filter { $0.kind == .flight },
      nonflight: segments.filter { $0.kind == .nonflight },
      incomplete: segments.filter { $0.kind == .incomplete }
    )
  }

  private func segments(of samples: [TrackSample], origin: Origin) -> [TrackSegment] {
    let settings = aircraftSettings(for: origin.registration)
    var result = [TrackSegment]()
    var session = [TrackSample]()
    var stationarySince: Date?
    var hadAir = false

    for sample in samples {
      if let last = session.last,
        startsNewSession(
          sample,
          after: last,
          stationarySince: stationarySince,
          hadAir: hadAir,
          settings: settings
        )
      {
        result.append(
          TrackSegment(
            registration: origin.registration,
            source: origin.source,
            samples: session,
            settings: settings
          )
        )
        session = []
        stationarySince = nil
        hadAir = false
      }
      session.append(sample)
      let speed = sample.groundSpeedKts
      if let speed, speed < settings.movementKts {
        stationarySince = stationarySince ?? sample.time
      } else {
        stationarySince = nil
      }
      if (speed ?? 0) > settings.airborneKts && sample.isOnGround != true { hadAir = true }
    }
    if !session.isEmpty {
      result.append(
        TrackSegment(
          registration: origin.registration,
          source: origin.source,
          samples: session,
          settings: settings
        )
      )
    }
    return result
  }

  private func startsNewSession(
    _ sample: TrackSample,
    after last: TrackSample,
    stationarySince: Date?,
    hadAir: Bool,
    settings: TrackDetectionSettings
  ) -> Bool {
    if sample.time.timeIntervalSince(last.time) > settings.gapSeconds { return true }
    guard hadAir, let stationarySince else { return false }
    return sample.time.timeIntervalSince(stationarySince) > settings.parkedSeconds
  }

  private func aircraftSettings(for registration: String) -> TrackDetectionSettings {
    guard let overrides = aircraft[registration]?.trackDetection else { return settings }
    return settings.applying(overrides)
  }

  private struct Origin: Hashable, Comparable {
    var registration: String
    var source: String

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.registration, lhs.source) < (rhs.registration, rhs.source)
    }
  }
}
