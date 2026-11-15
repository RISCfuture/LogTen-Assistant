import Audit
import Foundation
import LogbookModel
import Testing
import Tracks

/// A position the synthetic aircraft passes at a number of seconds after the start.
struct Keyframe {
  var seconds: Double
  var latitude: Double
  var longitude: Double
  var altitudeFt = 3_000.0
  var knots = 100.0
}

/// Samples every `step` seconds, interpolating linearly between keyframes.
func samples(through keyframes: [Keyframe], from start: Date, step: Double = 1) -> [TrackSample] {
  zip(keyframes, keyframes.dropFirst()).flatMap { first, second in
    stride(from: first.seconds, to: second.seconds, by: step).map { seconds in
      let fraction = (seconds - first.seconds) / (second.seconds - first.seconds)
      func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
      return TrackSample(
        time: start.addingTimeInterval(seconds),
        latitudeDeg: blend(first.latitude, second.latitude),
        longitudeDeg: blend(first.longitude, second.longitude),
        altitudeFt: blend(first.altitudeFt, second.altitudeFt),
        groundSpeedKts: blend(first.knots, second.knots)
      )
    }
  }
    + (keyframes.last.map { last in
      [
        TrackSample(
          time: start.addingTimeInterval(last.seconds),
          latitudeDeg: last.latitude,
          longitudeDeg: last.longitude,
          altitudeFt: last.altitudeFt,
          groundSpeedKts: last.knots
        )
      ]
    } ?? [])
}

/// A position offset from a reference by nautical miles east and north.
func offset(
  _ reference: (latitude: Double, longitude: Double),
  east: Double,
  north: Double
) -> (latitude: Double, longitude: Double) {
  (
    reference.latitude + north / 60,
    reference.longitude + east / (60 * cos(reference.latitude * .pi / 180))
  )
}

func event(
  _ kind: TrackEvent.Kind,
  at time: Date,
  _ latitude: Double,
  _ longitude: Double,
  confidence: TrackEvent.Confidence = .medium
) -> TrackEvent {
  TrackEvent(
    kind: kind,
    time: time,
    latitudeDeg: latitude,
    longitudeDeg: longitude,
    confidence: confidence
  )
}

/// A context for entry "A" whose segment is complete at both ends, to be adjusted by each test.
func baseContext() throws -> EvidenceContext {
  let flights = [flight("A")]
  let segment = flightSegment(startingAt: "2026-10-12T14:21:00Z", cruiseSeconds: 2_740)
  let correlation = try SegmentCorrelator().correlate([segment], with: flights)
  var context = try #require(
    try EvidenceContextBuilder(aircraft: [:], pilot: .init(), flights: flights).contexts(
      for: flights,
      records: [],
      flyStoMatches: [],
      segments: [segment],
      segmentMatches: correlation.matches
    )["A"]
  )
  context.adsbPoints = []
  context.points = []
  context.events = []
  context.times = [:]
  context.timeSources = [:]
  context.counts = [:]
  context.countSources = [:]
  return context
}

extension EvidenceContext {
  /// Replaces the positions with a track and sets the interval to match.
  mutating func fly(_ track: [TrackSample]) {
    points = track.map { EvidencePoint(sample: $0) }
    positionSource = .adsbLol
    start = track.first?.time
    end = track.last?.time
  }
}
