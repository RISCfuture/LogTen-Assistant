public import CoreLocation
public import Foundation

/// One position report in an aircraft track.
public struct TrackSample: Hashable, Codable, Sendable {
  /// When the position was reported.
  public var time: Date

  /// Latitude in degrees, north positive.
  public var latitudeDeg: Double

  /// Longitude in degrees, east positive.
  public var longitudeDeg: Double

  /// Pressure or geometric altitude in feet, if reported.
  public var altitudeFt: Double?

  /// Ground speed in knots, if reported.
  public var groundSpeedKts: Double?

  /// Whether the source reported the aircraft on the ground, if it reports that.
  public var isOnGround: Bool?

  /// The one-based position of the sample in the source it was read from, such as the point
  /// number in an ADS-B trace.
  public var sourceRow: Int?

  /// The position as a Core Location coordinate.
  public var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitudeDeg, longitude: longitudeDeg)
  }

  /// Creates a track sample.
  public init(
    time: Date,
    latitudeDeg: Double,
    longitudeDeg: Double,
    altitudeFt: Double? = nil,
    groundSpeedKts: Double? = nil,
    isOnGround: Bool? = nil,
    sourceRow: Int? = nil
  ) {
    self.time = time
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
    self.altitudeFt = altitudeFt
    self.groundSpeedKts = groundSpeedKts
    self.isOnGround = isOnGround
    self.sourceRow = sourceRow
  }
}

/// A time-ordered sequence of position reports for one aircraft from one source.
public struct Track: Hashable, Codable, Sendable {
  /// The aircraft's registration.
  public var registration: String

  /// The name of the source the samples came from, such as “adsb.lol”.
  public var source: String

  /// The samples, in time order.
  public var samples: [TrackSample]

  /// Where the samples came from, if known.
  public var provenance: SourceProvenance?

  /// The time from the first sample to the last, or `nil` for an empty track.
  public var interval: DateInterval? {
    guard let first = samples.first, let last = samples.last else { return nil }
    return DateInterval(start: first.time, end: last.time)
  }

  /// Creates a track, sorting its samples by time.
  public init(
    registration: String,
    source: String,
    samples: [TrackSample],
    provenance: SourceProvenance? = nil
  ) {
    self.registration = registration
    self.source = source
    self.samples = samples.sorted { $0.time < $1.time }
    self.provenance = provenance
  }

  /**
   Splits the track wherever consecutive samples are further apart than a gap, as when the
   aircraft was out of receiver coverage or parked between flights.

   - Parameter gap: The longest interval between samples that keeps them in one piece, in
     seconds.
   - Returns: The pieces, in time order; none for an empty track.
   */
  public func split(atGapsLongerThan gap: TimeInterval) -> [Self] {
    var pieces = [[TrackSample]]()
    for sample in samples {
      if let previous = pieces.last?.last, sample.time.timeIntervalSince(previous.time) <= gap {
        pieces[pieces.count - 1].append(sample)
      } else {
        pieces.append([sample])
      }
    }
    return pieces.map {
      Self(registration: registration, source: source, samples: $0, provenance: provenance)
    }
  }
}

/// A provider of aircraft tracks, such as an ADS-B archive or an onboard data log.
///
/// Event detection and segmentation work on any source's tracks, so a new source needs only to
/// produce ``Track`` values.
public protocol TrackSource: Sendable {
  /// The source's name, recorded with every track it provides.
  var name: String { get }

  /**
   Returns the tracks for an aircraft that overlap a time interval.

   - Parameters:
     - registration: The aircraft's registration.
     - interval: The interval to cover.
   - Returns: The tracks found, possibly none.
   */
  func tracks(for registration: String, during interval: DateInterval) async throws -> [Track]
}
