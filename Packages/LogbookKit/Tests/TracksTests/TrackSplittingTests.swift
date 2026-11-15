import Foundation
import Testing
import Tracks

@Suite
struct `Track splitting` {
  @Test
  func `splits where samples are further apart than the gap`() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let offsets: [TimeInterval] = [0, 5, 10, 200, 205, 1_000]
    let track = Track(
      registration: "N12345",
      source: "test",
      samples: offsets.reversed().map {
        TrackSample(time: start + $0, latitudeDeg: 37, longitudeDeg: -122)
      }
    )

    let pieces = track.split(atGapsLongerThan: 120)

    #expect(
      pieces.map { $0.samples.map { $0.time.timeIntervalSince(start) } } == [
        [0, 5, 10], [200, 205], [1_000]
      ]
    )
    #expect(pieces[0].interval?.duration == 10)
  }
}
