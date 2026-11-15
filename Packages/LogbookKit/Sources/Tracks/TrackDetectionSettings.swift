public import LogbookModel

/// The thresholds that turn a stream of position reports into takeoffs, landings and block
/// movement.
///
/// The defaults match cleanup-logten. Per-aircraft overrides from `AircraftSettings` replace
/// individual values through ``applying(_:)``.
public struct TrackDetectionSettings: Hashable, Codable, Sendable {
  /// The longest interval between samples that keeps them in one piece, in seconds.
  public var gapSeconds: Double = 120

  /// Ground speed above which the aircraft is moving under its own power, in knots.
  public var movementKts: Double = 3

  /// Speed at or above which the aircraft is airborne, in knots.
  public var airborneKts: Double = 55

  /// Speed at or below which the aircraft is on the ground, in knots.
  public var groundKts: Double = 35

  /// How long a change between ground and air must hold before it is confirmed, in seconds.
  public var confirmSeconds: Double = 10

  /// How long the aircraft must be stopped before movement ends, in seconds.
  public var stopSeconds: Double = 60

  /// How long the aircraft must be stationary after landing for a landing to be a full stop,
  /// in seconds.
  public var fullStopSeconds: Double = 3

  /// Ground speed at or below which the aircraft is stationary for a full stop, in knots.
  public var fullStopKts: Double = 0.5

  /// How long a stationary aircraft may sit after flying before a new segment starts, in
  /// seconds.
  public var parkedSeconds: Double = 600

  /// Creates settings with cleanup-logten's defaults.
  public init() {}

  /// Returns the settings with an aircraft's overrides applied.
  public func applying(_ overrides: TrackDetectionOverrides) -> Self {
    var result = self
    result.airborneKts = overrides.airborneSpeedKts ?? airborneKts
    result.groundKts = overrides.groundSpeedKts ?? groundKts
    result.confirmSeconds = overrides.confirmSeconds ?? confirmSeconds
    result.stopSeconds = overrides.stopSeconds ?? stopSeconds
    result.gapSeconds = overrides.gapSeconds ?? gapSeconds
    return result
  }
}
