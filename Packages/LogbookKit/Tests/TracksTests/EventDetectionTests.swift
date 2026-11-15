import Foundation
import LogbookModel
import Testing

@testable import Tracks

/// A one-hertz track assembled from `(seconds, speed, isOnGround)` runs.
struct SyntheticTrack {
  static let origin = Date(timeIntervalSince1970: 1_700_000_000)

  private(set) var samples = [TrackSample]()
  private var elapsed = 0.0
  var track: Track { Track(registration: "N12345", source: "test", samples: samples) }

  /// Parked, taxi, takeoff roll, cruise, landing roll, taxi back and park.
  static func fullFlight(startingAt start: Double = 0) -> Self {
    var track = Self()
    track.hold(30, knots: 0, onGround: true, startingAt: start)
    track.hold(30, knots: 10, onGround: true)
    track.hold(20, knots: 90)
    track.hold(100, knots: 120)
    track.hold(20, knots: 60, onGround: true)
    track.hold(30, knots: 10, onGround: true)
    track.hold(90, knots: 0, onGround: true)
    return track
  }

  mutating func hold(
    _ seconds: Int,
    knots: Double,
    onGround: Bool? = nil,
    startingAt start: Double? = nil
  ) {
    elapsed = start ?? elapsed
    for _ in 0..<seconds {
      samples.append(
        TrackSample(
          time: Self.origin + elapsed,
          latitudeDeg: 37,
          longitudeDeg: -122,
          groundSpeedKts: knots,
          isOnGround: onGround
        )
      )
      elapsed += 1
    }
  }
}

@Suite
struct `Track event detection` {
  @Test
  func `finds block movement, takeoff, landing and full stop in a flight`() {
    let events = SyntheticTrack.fullFlight().track.detectEvents()

    let kinds = events.map(\.kind)
    #expect(kinds == [.out, .takeoff, .fullStop, .landing, .in])
    let offsets = events.map { $0.time.timeIntervalSince(SyntheticTrack.origin) }
    #expect(offsets == [30, 60, 180, 180, 230])
  }

  @Test
  func `reports a touch-and-go when the aircraft takes off again without stopping`() {
    var track = SyntheticTrack()
    track.hold(30, knots: 0, onGround: true)
    track.hold(20, knots: 90)
    track.hold(60, knots: 120)
    track.hold(20, knots: 30, onGround: true)
    track.hold(20, knots: 90)
    track.hold(60, knots: 120)

    let kinds = track.track.detectEvents().map(\.kind)

    #expect(kinds == [.out, .takeoff, .landing, .touchAndGo, .takeoff])
  }

  @Test
  func `confirms a landing only after the new state holds for the confirmation time`() {
    var track = SyntheticTrack()
    track.hold(30, knots: 0, onGround: true)
    track.hold(20, knots: 90)
    track.hold(60, knots: 120)
    track.hold(5, knots: 20, onGround: true)
    track.hold(40, knots: 120)

    let kinds = track.track.detectEvents().map(\.kind)

    #expect(kinds == [.takeoff])
  }

  @Test
  func `marks a gap and starts over after it`() {
    var track = SyntheticTrack.fullFlight()
    track.hold(30, knots: 0, onGround: true, startingAt: 1_000)

    let events = track.track.detectEvents()

    #expect(events.contains { $0.kind == .gap })
  }
}

@Suite
struct `Track segmentation` {
  @Test
  func `splits at gaps and classifies each piece`() {
    var track = SyntheticTrack.fullFlight()
    var second = SyntheticTrack.fullFlight(startingAt: 3_000)
    track.hold(1, knots: 0)
    second.hold(1, knots: 0)
    let result = TrackSegmenter().segment([track.track, second.track])

    #expect(result.flights.count == 2)
    #expect(result.nonflight.isEmpty)
    #expect(result.flights[0].events.map(\.kind) == [.out, .takeoff, .fullStop, .landing, .in])
  }

  @Test
  func `classifies a parked session as nonflight and a partial one as incomplete`() {
    var parked = SyntheticTrack()
    parked.hold(120, knots: 0, onGround: true)
    var partial = SyntheticTrack()
    partial.hold(60, knots: 120, startingAt: 10_000)
    partial.hold(20, knots: 30, onGround: true)
    partial.hold(40, knots: 0, onGround: true)

    let result = TrackSegmenter().segment([parked.track, partial.track])

    #expect(result.nonflight.count == 1)
    #expect(result.incomplete.count == 1)
    #expect(result.flights.isEmpty)
  }

  @Test
  func `applies a per-aircraft airborne threshold`() {
    let track = SyntheticTrack.fullFlight().track
    let aircraft = [
      "N12345": AircraftSettings(trackDetection: .init(airborneSpeedKts: 150))
    ]

    let result = TrackSegmenter(aircraft: aircraft).segment([track])

    #expect(result.flights.isEmpty)
  }

  @Test
  func `starts a new segment after the aircraft sits parked following a flight`() {
    var track = SyntheticTrack()
    track.hold(30, knots: 0, onGround: true)
    track.hold(20, knots: 90)
    track.hold(60, knots: 120)
    track.hold(700, knots: 0, onGround: true)

    let result = TrackSegmenter().segment([track.track])

    #expect(result.flights.count == 1)
    #expect(result.nonflight.count == 1)
  }
}
