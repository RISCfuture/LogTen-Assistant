import FlightSources
import Foundation
public import LogbookModel
import Tracks

extension RecordID: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

func utc(_ text: String) -> Date {
  guard let date = try? Date(text, strategy: .iso8601) else {
    preconditionFailure("Invalid test date \(text)")
  }
  return date
}

func place(_ identifier: String) -> Place {
  Place(
    id: RecordID(rawValue: "place-\(identifier)"),
    identifier: identifier,
    ICAO: "K\(identifier)"
  )
}

/// A logbook entry with Zulu clock times on 2026-10-12.
func flight(
  _ id: String,
  tail: String = "N111AA",
  out: String? = "2026-10-12T14:10:00Z",
  off: String? = "2026-10-12T14:22:00Z",
  on: String? = "2026-10-12T15:08:00Z",
  `in`: String? = "2026-10-12T15:15:00Z",
  from: String? = "SQL",
  to: String? = "RHV",
  takeoffs: UInt = 1,
  landings: UInt = 1,
  fullStops: UInt = 1,
  crew: FlightCrew = .init()
) -> Flight {
  Flight(
    id: RecordID(rawValue: id),
    date: utc("2026-10-12T00:00:00Z"),
    flightKey: "key-\(id)",
    aircraft: Aircraft(id: RecordID(rawValue: "aircraft-\(tail)"), registration: tail),
    from: from.map(place),
    to: to.map(place),
    events: FlightEvents(
      out: out.map(utc),
      off: off.map(utc),
      on: on.map(utc),
      in: `in`.map(utc)
    ),
    counts: FlightCounts(
      dayTakeoffs: takeoffs,
      dayLandings: landings,
      fullStops: fullStops
    ),
    crew: crew
  )
}

func person(_ id: String) -> Person {
  Person(id: RecordID(rawValue: id), name: id)
}

/// A FlySto record for the same flight as ``flight(_:)`` unless overridden.
func record(
  _ id: String = "rec",
  tail: String = "N111AA",
  out: String? = "2026-10-12T14:10:00Z",
  takeoff: String? = "2026-10-12T14:22:00Z",
  landing: String? = "2026-10-12T15:08:00Z",
  `in`: String? = "2026-10-12T15:15:00Z",
  from: String? = "KSQL",
  to: String? = "KRHV",
  takeoffs: UInt? = 1,
  landings: UInt? = 1,
  conflicts: Set<FlyStoField> = [],
  timeIssues: [FlyStoTimeIssue] = []
) -> FlyStoRecord {
  let times = FlyStoTimes(
    out: out.map(utc),
    takeoff: takeoff.map(utc),
    landing: landing.map(utc),
    in: `in`.map(utc)
  )
  let counts = FlyStoCounts(takeoffs: takeoffs, landings: landings)
  return FlyStoRecord(
    id: id,
    origin: .csvExport,
    registration: tail,
    day: utc("2026-10-12T00:00:00Z"),
    from: from,
    to: to,
    times: times,
    counts: counts,
    conflicts: conflicts,
    timeIssues: timeIssues,
    rows: [FlyStoRow(file: "export.csv", number: 3, times: times, counts: counts)],
    precision: 60
  )
}

/// A track segment of a complete flight: 30 s parked, 30 s taxi, a takeoff roll, a cruise, a
/// landing roll, taxi and parking. Brakes off is 30 s in, takeoff 60 s in.
func flightSegment(
  tail: String = "N111AA",
  startingAt start: String = "2026-10-12T14:10:00Z",
  cruiseSeconds: Int = 2_700,
  source: String = "adsb.lol",
  latitude: Double = 37
) -> TrackSegment {
  var samples = [TrackSample]()
  var time = utc(start)
  func hold(_ seconds: Int, knots: Double, onGround: Bool?) {
    for _ in 0..<seconds {
      samples.append(
        TrackSample(
          time: time,
          latitudeDeg: latitude,
          longitudeDeg: -122,
          groundSpeedKts: knots,
          isOnGround: onGround
        )
      )
      time += 1
    }
  }
  hold(30, knots: 0, onGround: true)
  hold(30, knots: 10, onGround: true)
  hold(20, knots: 90, onGround: nil)
  hold(cruiseSeconds, knots: 120, onGround: nil)
  hold(20, knots: 60, onGround: true)
  hold(30, knots: 10, onGround: true)
  hold(90, knots: 0, onGround: true)
  let segments = TrackSegmenter().segment([
    Track(registration: tail, source: source, samples: samples)
  ])
  return segments.flights[0]
}
