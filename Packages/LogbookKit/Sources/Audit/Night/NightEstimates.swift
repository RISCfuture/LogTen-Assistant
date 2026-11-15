public import Foundation
public import LogbookModel
import References
public import Tracks

/// How many minutes of an interval the aircraft spent in civil night, judged from its sampled
/// track with bounds for what the samples can't show.
///
/// Only adjacent samples at most a gap apart are interpolated; missing positions and longer gaps
/// stay unknown. The estimate integrates linear solar-elevation crossings over covered intervals
/// only. The bounds add a margin for the Sun's change and the aircraft's movement between
/// samples, and give an unobserved interval no night at the lower bound and all of it at the
/// upper. They are review evidence, not an Air Almanac certification.
public struct TrackNightEstimate: Hashable, Codable, Sendable {
  /// The civil-twilight threshold: the geometric center of the Sun strictly below this
  /// elevation, in degrees, is night.
  public static let thresholdDegrees = NightWindow.civilTwilightElevation

  /// Where the twilight definition is published.
  public static let reference = "https://aa.usno.navy.mil/faq/RST_defs"

  private static let secondsPerMinute = 60.0
  private static let solarChangeDegreesPerSecond = 0.005
  private static let baseMarginDegrees = 0.1

  /// Night minutes over the covered part of the interval.
  public var estimateMinutes: Double
  /// The fewest night minutes the samples allow.
  public var minimumMinutes: Double
  /// The most night minutes the samples allow.
  public var maximumMinutes: Double
  /// The length of the interval.
  public var intervalMinutes: Double
  /// The minutes between usable adjacent samples.
  public var coveredMinutes: Double
  /// The covered minutes that are certainly day or certainly night.
  public var classifiedMinutes: Double
  /// The width of the bounds.
  public var unknownMinutes: Double
  /// The minutes without usable samples around them.
  public var missingMinutes: Double
  /// The covered minutes near a twilight crossing that can't be classified.
  public var transitionUncertaintyMinutes: Double

  /// The estimate as the evidence of a finding records it.
  public var jsonValue: JSONValue {
    [
      "estimate_minutes": .double(estimateMinutes),
      "min": .double(minimumMinutes),
      "max": .double(maximumMinutes),
      "interval_minutes": .double(intervalMinutes),
      "covered_minutes": .double(coveredMinutes),
      "classified_minutes": .double(classifiedMinutes),
      "unknown_minutes": .double(unknownMinutes),
      "missing_minutes": .double(missingMinutes),
      "transition_uncertainty_minutes": .double(transitionUncertaintyMinutes),
      "threshold_degrees": .integer(Int(Self.thresholdDegrees)),
      "with_refraction": .bool(false),
      "reference": .string(Self.reference)
    ]
  }

  /**
   Estimates the night minutes of an interval.

   - Parameters:
     - samples: The track, in time order, with valid positions.
     - start: The start of the interval.
     - end: The end of the interval; it must be after `start`.
     - gapSeconds: The longest interval between samples that is still interpolated.
   - Returns: The estimate, or `nil` if the interval or gap isn't positive.
   */
  public init?(samples: [TrackSample], from start: Date, to end: Date, gapSeconds: Double = 120) {
    guard end > start, gapSeconds > 0 else { return nil }
    let total = end.timeIntervalSince(start) / Self.secondsPerMinute
    var accumulator = Accumulator()
    for (left, right) in zip(samples, samples.dropFirst()) {
      accumulator.add(left, right, start: start, end: end, gapSeconds: gapSeconds)
    }
    let maximum = accumulator.minimum + total - accumulator.known
    estimateMinutes = accumulator.estimate
    minimumMinutes = accumulator.minimum
    maximumMinutes = maximum
    intervalMinutes = total
    coveredMinutes = accumulator.covered
    classifiedMinutes = accumulator.known
    unknownMinutes = max(0, maximum - accumulator.minimum)
    missingMinutes = max(0, total - accumulator.covered)
    transitionUncertaintyMinutes = max(0, accumulator.covered - accumulator.known)
  }

  private struct Accumulator {
    var minimum = 0.0
    var known = 0.0
    var estimate = 0.0
    var covered = 0.0

    mutating func add(
      _ left: TrackSample,
      _ right: TrackSample,
      start: Date,
      end: Date,
      gapSeconds: Double
    ) {
      let from = max(start, left.time)
      let to = min(end, right.time)
      let delta = right.time.timeIntervalSince(left.time)
      guard to > from, delta > 0, delta <= gapSeconds, left.hasValidPosition,
        right.hasValidPosition
      else { return }
      let longitude = abs(
        (right.longitudeDeg - left.longitudeDeg + 540).truncatingRemainder(dividingBy: 360) - 180
      )
      let movement = abs(right.latitudeDeg - left.latitudeDeg) + longitude
      let margin =
        (delta * TrackNightEstimate.solarChangeDegreesPerSecond + movement) / 2
        + TrackNightEstimate.baseMarginDegrees
      let angles = (elevation(of: left), elevation(of: right))
      let (low, high) = (min(angles.0, angles.1), max(angles.0, angles.1))
      let minutes = to.timeIntervalSince(from) / TrackNightEstimate.secondsPerMinute
      covered += minutes
      estimate +=
        nightSeconds(left.time, right.time, from, to, angles.0, angles.1)
        / TrackNightEstimate.secondsPerMinute
      let threshold = TrackNightEstimate.thresholdDegrees
      if high + margin < threshold {
        minimum += minutes
        known += minutes
      } else if low - margin >= threshold {
        known += minutes
      }
    }

    private func elevation(of sample: TrackSample) -> Double {
      SolarPosition.elevation(
        at: sample.time,
        latitudeDeg: sample.latitudeDeg,
        longitudeDeg: sample.longitudeDeg
      )
    }

    /// The seconds of `from...to` below the threshold, taking the elevation to change
    /// linearly between the two samples.
    private func nightSeconds(
      _ left: Date,
      _ right: Date,
      _ from: Date,
      _ to: Date,
      _ angleLeft: Double,
      _ angleRight: Double
    ) -> Double {
      let threshold = TrackNightEstimate.thresholdDegrees
      let leftIsNight = angleLeft < threshold
      let rightIsNight = angleRight < threshold
      if leftIsNight && rightIsNight { return to.timeIntervalSince(from) }
      if leftIsNight == rightIsNight { return 0 }
      let crossing = left.addingTimeInterval(
        right.timeIntervalSince(left) * (threshold - angleLeft) / (angleRight - angleLeft)
      )
      return leftIsNight
        ? max(0, min(to, crossing).timeIntervalSince(from))
        : max(0, to.timeIntervalSince(max(from, crossing)))
    }
  }
}

/// A comparison with a simple model of how LogTen is described to count night time: the flight
/// as a constant-speed great circle from origin to destination, cut into six-minute chunks
/// classified by their midpoints.
///
/// This is a user-described model, not a reproduction of LogTen's algorithm. The alternatives
/// that classify each chunk by its start or end show how sensitive the result is to the unknown
/// chunk convention.
public struct EndpointNightComparison: Hashable, Codable, Sendable {
  /// The chunk length, in seconds.
  public static let chunkSeconds = 360.0

  private static let antipodalDistanceNM = 10_790.0

  /// Night minutes classifying each chunk by its midpoint.
  public var estimateMinutes: Double
  /// Night minutes classifying each chunk by its start.
  public var startSampleMinutes: Double
  /// Night minutes classifying each chunk by its end.
  public var endSampleMinutes: Double
  /// The length of the interval.
  public var intervalMinutes: Double

  /// The lowest of the three estimates.
  public var samplingMinimumMinutes: Double {
    min(estimateMinutes, startSampleMinutes, endSampleMinutes)
  }

  /// The highest of the three estimates.
  public var samplingMaximumMinutes: Double {
    max(estimateMinutes, startSampleMinutes, endSampleMinutes)
  }

  /// The estimate as the evidence of a finding records it.
  public var jsonValue: JSONValue {
    [
      "available": .bool(true),
      "estimate_minutes": .double(estimateMinutes),
      "start_sample_minutes": .double(startSampleMinutes),
      "end_sample_minutes": .double(endSampleMinutes),
      "sampling_min_minutes": .double(samplingMinimumMinutes),
      "sampling_max_minutes": .double(samplingMaximumMinutes),
      "interval_minutes": .double(intervalMinutes),
      "chunk_seconds": .double(Self.chunkSeconds)
    ]
  }

  /**
   Models a flight between two positions.

   - Parameters:
     - start: The start of the logged interval.
     - end: The end of the logged interval; it must be after `start`.
     - origin: The departure position, as latitude and longitude in degrees.
     - destination: The arrival position.
   - Returns: The comparison, or `nil` if the interval is empty or the endpoints are antipodal
     or invalid.
   */
  public init?(
    from start: Date,
    to end: Date,
    origin: (latitudeDeg: Double, longitudeDeg: Double),
    destination: (latitudeDeg: Double, longitudeDeg: Double)
  ) {
    guard end > start, Self.isValid(origin), Self.isValid(destination),
      GreatCircle.distanceNM(
        origin.latitudeDeg,
        origin.longitudeDeg,
        destination.latitudeDeg,
        destination.longitudeDeg
      ) < Self.antipodalDistanceNM
    else { return nil }
    let sampled = [0.0, 0.5, 1.0].map {
      Self.nightMinutes(from: start, to: end, origin, destination, offset: $0)
    }
    estimateMinutes = sampled[1]
    startSampleMinutes = sampled[0]
    endSampleMinutes = sampled[2]
    intervalMinutes = end.timeIntervalSince(start) / 60
  }

  private static func isValid(_ position: (latitudeDeg: Double, longitudeDeg: Double)) -> Bool {
    (-90...90).contains(position.latitudeDeg) && (-180...180).contains(position.longitudeDeg)
  }

  private static func nightMinutes(
    from start: Date,
    to end: Date,
    _ origin: (latitudeDeg: Double, longitudeDeg: Double),
    _ destination: (latitudeDeg: Double, longitudeDeg: Double),
    offset: Double
  ) -> Double {
    let span = end.timeIntervalSince(start)
    var night = 0.0
    var chunkStart = start
    while chunkStart < end {
      let chunkEnd = min(end, chunkStart.addingTimeInterval(chunkSeconds))
      let moment = chunkStart.addingTimeInterval(chunkEnd.timeIntervalSince(chunkStart) * offset)
      let position = GreatCircle.interpolate(
        origin.latitudeDeg,
        origin.longitudeDeg,
        destination.latitudeDeg,
        destination.longitudeDeg,
        fraction: moment.timeIntervalSince(start) / span
      )
      if SolarPosition.elevation(
        at: moment,
        latitudeDeg: position.latitudeDeg,
        longitudeDeg: position.longitudeDeg
      ) < NightWindow.civilTwilightElevation {
        night += chunkEnd.timeIntervalSince(chunkStart) / 60
      }
      chunkStart = chunkEnd
    }
    return night
  }
}
