public import Foundation

/// Something that happened to an aircraft, inferred from its track.
public struct TrackEvent: Hashable, Codable, Sendable {
  /// The kind of event.
  public var kind: Kind

  /// When the event happened, to the precision of the track.
  public var time: Date

  /// Latitude of the aircraft at the event, if the sample had a position.
  public var latitudeDeg: Double?

  /// Longitude of the aircraft at the event, if the sample had a position.
  public var longitudeDeg: Double?

  /// How strongly the track supports the event.
  public var confidence: Confidence

  /// The identifier of the airport the event happened at, once a reference lookup has
  /// resolved it.
  public var airport: String?

  /// The one-based sample position in the source that triggered the event.
  public var sourceRow: Int?

  /// Creates an event.
  public init(
    kind: Kind,
    time: Date,
    latitudeDeg: Double? = nil,
    longitudeDeg: Double? = nil,
    confidence: Confidence = .medium,
    airport: String? = nil,
    sourceRow: Int? = nil
  ) {
    self.kind = kind
    self.time = time
    self.latitudeDeg = latitudeDeg
    self.longitudeDeg = longitudeDeg
    self.confidence = confidence
    self.airport = airport
    self.sourceRow = sourceRow
  }

  init(_ kind: Kind, at sample: TrackSample, confidence: Confidence = .medium) {
    self.init(
      kind: kind,
      time: sample.time,
      latitudeDeg: sample.latitudeDeg,
      longitudeDeg: sample.longitudeDeg,
      confidence: confidence,
      sourceRow: sample.sourceRow
    )
  }

  /// What kind of event this is.
  public enum Kind: String, CaseIterable, Codable, Sendable {
    /// The aircraft left the ground.
    case takeoff
    /// The aircraft touched down.
    case landing
    /// The aircraft came to rest after landing.
    case fullStop = "full_stop"
    /// The aircraft touched down and took off again without stopping.
    case touchAndGo = "touch_and_go"
    /// The aircraft began moving on the ground before a flight (brakes off).
    case out
    /// The aircraft stopped moving after landing (brakes on).
    case `in`
    /// The aircraft stopped moving without having landed in the track.
    case groundStop = "ground_stop"
    /// Samples are missing before this point.
    case gap
  }

  /// How strongly the track supports an event.
  public enum Confidence: String, Codable, Sendable {
    /// The track only hints at the event.
    case low
    /// The track shows the event under the detector's thresholds.
    case medium
  }
}
