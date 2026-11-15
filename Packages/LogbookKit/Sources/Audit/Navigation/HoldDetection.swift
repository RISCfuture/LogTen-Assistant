public import Foundation
public import LogbookModel
import References
public import Tracks

/// A stretch of track that looks like a holding pattern.
public struct HoldCandidate: Hashable, Codable, Sendable {

  /// When the first leg began.
  public var start: Date
  /// When the last leg ended.
  public var end: Date
  /// How many reciprocal straight legs the pattern has.
  public var reciprocalLegs: Int
  /// The farthest any leg's end is from the end of the leg two before it, in nautical miles.
  public var recurrenceNM: Double
  /// The spread of altitudes over the pattern, in feet.
  public var altitudeRangeFt: Double
  /// The direction of the turns.
  public var turnDirection: TurnDirection

  /// The candidate as the evidence of a finding records it.
  public var jsonValue: JSONValue {
    [
      "start": .string(start.formatted(.iso8601)),
      "end": .string(end.formatted(.iso8601)),
      "reciprocal_legs": .integer(reciprocalLegs),
      "recurrence_nm": .double((recurrenceNM * 1_000).rounded() / 1_000),
      "altitude_range_feet": .double((altitudeRangeFt * 10).rounded() / 10),
      "basis": "repeated_reciprocal_straight_legs",
      "turn_direction": .string(turnDirection.rawValue),
      "confirmed_hold": .bool(false)
    ]
  }

  /// Which way the aircraft turned at the ends of the pattern.
  public enum TurnDirection: String, Codable, Sendable {
    /// Clockwise turns.
    case right
    /// Counterclockwise turns.
    case left
  }
}

/// Finds holding-pattern candidates in a track: five straight legs in alternating directions,
/// one above another, turning the same way, at a steady altitude, with continuous coverage.
///
/// This is geometry only. Loitering and maneuvering can look the same, so a candidate never
/// establishes a hold or a count.
public struct HoldDetector: Sendable {

  private static let legsPerPattern = 5
  private static let minimumTurnSeconds = 10.0
  private static let reciprocalRangeDegrees = 150.0...180.0
  private static let rotationRangeDegrees = 135.0...225.0
  private static let legDurationSpread = 1.8
  private static let minimumTurnStepNM = 0.01

  private let thresholds: Thresholds

  /// Creates a detector.
  public init(thresholds: Thresholds = .init()) {
    self.thresholds = thresholds
  }

  /// The signed change of course from one bearing to another, in degrees from −180 up to 180.
  private static func signedTurn(from first: Double, to second: Double) -> Double {
    (second - first + 540).truncatingRemainder(dividingBy: 360) - 180
  }

  /**
   Finds the hold candidates in a track.

   - Parameter samples: The track, in time order, with altitude and ground speed.
   - Returns: The candidates, in time order and not overlapping.

   */
  public func candidates(in samples: [TrackSample]) -> [HoldCandidate] {
    let legs = straightLegs(samples)
    var result = [HoldCandidate]()
    guard legs.count >= Self.legsPerPattern else { return [] }
    for offset in 0...(legs.count - Self.legsPerPattern) {
      let group = Array(legs[offset..<offset + Self.legsPerPattern])
      if let last = result.last, group[0].start.time <= last.end { continue }
      if let candidate = candidate(from: group, samples: samples) { result.append(candidate) }
    }
    return result
  }

  private func candidate(from group: [Leg], samples: [TrackSample]) -> HoldCandidate? {
    guard areReciprocalAndPaced(group),
      group.allSatisfy({ $0.duration <= thresholds.maximumLegSeconds })
    else { return nil }
    let recurrence = recurrence(of: group)
    guard recurrence <= thresholds.recurrenceNM else { return nil }
    let start = group[0].start.time
    let end = group[group.count - 1].end.time
    let rows = samples.filter { $0.time >= start && $0.time <= end }
    guard
      zip(rows, rows.dropFirst()).allSatisfy({
        $1.time.timeIntervalSince($0.time) <= thresholds.maximumGapSeconds
      })
    else { return nil }
    let turns = zip(group, group.dropFirst()).map { first, second in
      turnDirection(
        rows.filter { $0.time >= first.end.time && $0.time <= second.start.time }
      )
    }
    guard let firstTurn = turns.first, let direction = firstTurn,
      turns.allSatisfy({ $0 == direction })
    else {
      return nil
    }
    let altitudes = rows.compactMap(\.altitudeFt)
    guard altitudes.count == rows.count, let high = altitudes.max(), let low = altitudes.min(),
      high - low <= thresholds.altitudeRangeFt
    else { return nil }
    let durations = group.map(\.duration).sorted()
    guard durations[durations.count - 1] <= Self.legDurationSpread * durations[durations.count / 2]
    else { return nil }
    return HoldCandidate(
      start: start,
      end: end,
      reciprocalLegs: group.count,
      recurrenceNM: recurrence,
      altitudeRangeFt: high - low,
      turnDirection: direction > 0 ? .right : .left
    )
  }

  private func areReciprocalAndPaced(_ group: [Leg]) -> Bool {
    zip(group, group.dropFirst()).allSatisfy { first, second in
      Self.reciprocalRangeDegrees.contains(GreatCircle.angleBetween(first.heading, second.heading))
        && (Self.minimumTurnSeconds...thresholds.maximumTurnSeconds).contains(
          second.start.time.timeIntervalSince(first.end.time)
        )
    }
  }

  /// How far the leg ends stray from those of the leg two before, the most for any of the first
  /// three legs.
  private func recurrence(of group: [Leg]) -> Double {
    let pairs = (0..<3).flatMap { index in
      [(group[index].start, group[index + 2].start), (group[index].end, group[index + 2].end)]
    }
    let distances = pairs.map {
      GreatCircle.distanceNM($0.latitudeDeg, $0.longitudeDeg, $1.latitudeDeg, $1.longitudeDeg)
    }
    return distances.max() ?? 0
  }

  private func straightLegs(_ samples: [TrackSample]) -> [Leg] {
    var legs = [Leg]()
    var current = [TrackSample]()
    var heading: Double?
    func flush() {
      if let first = current.first, let last = current.last,
        last.time.timeIntervalSince(first.time) >= thresholds.minimumLegSeconds,
        GreatCircle.distanceNM(
          first.latitudeDeg,
          first.longitudeDeg,
          last.latitudeDeg,
          last.longitudeDeg
        )
          >= thresholds.minimumLegNM
      {
        legs.append(
          Leg(
            start: first,
            end: last,
            heading: GreatCircle.bearingDeg(
              first.latitudeDeg,
              first.longitudeDeg,
              last.latitudeDeg,
              last.longitudeDeg
            )
          )
        )
      }
      current.removeAll()
    }
    for (first, second) in zip(samples, samples.dropFirst()) {
      let interval = second.time.timeIntervalSince(first.time)
      guard let firstSpeed = first.groundSpeedKts, let secondSpeed = second.groundSpeedKts,
        first.altitudeFt != nil, second.altitudeFt != nil, interval > 0,
        interval <= thresholds.maximumGapSeconds,
        min(firstSpeed, secondSpeed) >= thresholds.minimumSpeedKnots
      else {
        flush()
        heading = nil
        continue
      }
      let course = GreatCircle.bearingDeg(
        first.latitudeDeg,
        first.longitudeDeg,
        second.latitudeDeg,
        second.longitudeDeg
      )
      if let heading,
        GreatCircle.angleBetween(heading, course) > thresholds.straightToleranceDegrees
      {
        flush()
      }
      if current.isEmpty {
        current.append(first)
        heading = course
      }
      current.append(second)
    }
    flush()
    return legs
  }

  /// The way the course turned through a sample run, if it turned about half a circle:
  /// positive for clockwise, negative for counterclockwise.
  private func turnDirection(_ rows: [TrackSample]) -> Int? {
    let steps = zip(rows, rows.dropFirst()).filter {
      GreatCircle.distanceNM($0.latitudeDeg, $0.longitudeDeg, $1.latitudeDeg, $1.longitudeDeg)
        >= Self.minimumTurnStepNM
    }
    let courses = steps.map {
      GreatCircle.bearingDeg($0.latitudeDeg, $0.longitudeDeg, $1.latitudeDeg, $1.longitudeDeg)
    }
    let rotation = zip(courses, courses.dropFirst()).reduce(0.0) {
      $0 + Self.signedTurn(from: $1.0, to: $1.1)
    }
    guard Self.rotationRangeDegrees.contains(abs(rotation)) else { return nil }
    return rotation > 0 ? 1 : -1
  }

  private struct Leg {
    var start: TrackSample
    var end: TrackSample
    var heading: Double
    var duration: TimeInterval { end.time.timeIntervalSince(start.time) }
  }

  /// The thresholds that decide what looks like a hold.
  public struct Thresholds: Hashable, Codable, Sendable {
    /// The longest interval between samples that is still continuous, in seconds.
    public var maximumGapSeconds = 30.0
    /// How far a leg's course may wander, in degrees.
    public var straightToleranceDegrees = 12.0
    /// The shortest leg, in seconds.
    public var minimumLegSeconds = 40.0
    /// The shortest leg, in nautical miles.
    public var minimumLegNM = 0.5
    /// The slowest ground speed, in knots.
    public var minimumSpeedKnots = 55.0
    /// The longest turn between legs, in seconds.
    public var maximumTurnSeconds = 150.0
    /// The longest leg, in seconds.
    public var maximumLegSeconds = 180.0
    /// How far apart the ends of alternate legs may be, in nautical miles.
    public var recurrenceNM = 0.35
    /// The widest altitude spread, in feet.
    public var altitudeRangeFt = 400.0

    /// Creates the default thresholds.
    public init() {}
  }
}
