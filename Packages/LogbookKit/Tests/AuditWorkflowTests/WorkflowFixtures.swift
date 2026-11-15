import FlightSources
import Foundation
public import LogbookModel
import Synchronization

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

/// A logbook entry flown SQL to RHV on 2026-10-12, out 14:10Z and in 15:15Z.
func flight(
  _ id: String,
  flightKey: String? = nil,
  isLocked: Bool = false,
  times: FlightTimes = FlightTimes(total: 65, PIC: 65),
  in arrival: String = "2026-10-12T15:15:00Z"
) -> Flight {
  Flight(
    id: RecordID(rawValue: id),
    date: utc("2026-10-12T00:00:00Z"),
    flightKey: flightKey ?? "key-\(id)",
    isLocked: isLocked,
    aircraft: Aircraft(
      id: RecordID(rawValue: "aircraft-N111AA"),
      registration: "N111AA",
      type: AircraftType(
        id: "type-C172",
        type: "C172",
        category: .airplane,
        aircraftClass: .singleEngineLand,
        engineType: .reciprocating
      )
    ),
    from: place("SQL"),
    to: place("RHV"),
    events: FlightEvents(
      out: utc("2026-10-12T14:10:00Z"),
      off: utc("2026-10-12T14:22:00Z"),
      on: utc("2026-10-12T15:08:00Z"),
      in: utc(arrival)
    ),
    times: times,
    counts: FlightCounts(dayTakeoffs: 1, dayLandings: 1, fullStops: 1)
  )
}

/// A FlySto record of ``flight(_:flightKey:isLocked:times:in:)``'s flight, landing in at
/// `in`.
func record(
  _ id: String = "rec",
  origin: FlyStoRecord.Origin = .csvExport,
  from: String = "KSQL",
  to: String = "KRHV",
  in arrival: String = "2026-10-12T15:25:00Z"
) -> FlyStoRecord {
  let times = FlyStoTimes(
    out: utc("2026-10-12T14:10:00Z"),
    takeoff: utc("2026-10-12T14:22:00Z"),
    landing: utc("2026-10-12T15:08:00Z"),
    in: utc(arrival)
  )
  let counts = FlyStoCounts(takeoffs: 1, landings: 1)
  return FlyStoRecord(
    id: id,
    origin: origin,
    registration: "N111AA",
    day: utc("2026-10-12T00:00:00Z"),
    from: from,
    to: to,
    times: times,
    counts: counts,
    rows: [FlyStoRow(file: "export.csv", number: 3, times: times, counts: counts)],
    precision: 60
  )
}

/// A logbook of flights, each fingerprinted by its arrival time and lock state.
func logbook(_ flights: [Flight]) -> Logbook {
  Logbook(
    identity: LogbookIdentity(
      storeUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID(),
      modelVersionIdentifiers: ["test"]
    ),
    flights: flights,
    aircraft: Array(Set(flights.compactMap(\.aircraft))),
    fingerprints: Dictionary(
      uniqueKeysWithValues: flights.map { flight in
        (
          flight.id,
          RecordFingerprint(
            rawValue: "\(flight.events.in?.timeIntervalSince1970 ?? 0)-\(flight.isLocked)"
          )
        )
      }
    )
  )
}

/// A FlySto API that answers `GET /logs` with one page per call, in order, and records each
/// request's URL.
final class StubFlyStoAPI: HTTPTransport {
  private let pages: Mutex<[String]>
  private let seen = Mutex<[URL]>([])

  var requestedURLs: [URL] { seen.withLock { $0 } }

  init(pages: [String]) {
    self.pages = Mutex(pages)
  }

  // swiftlint:disable:next async_without_await
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard let url = request.url else { throw URLError(.badURL) }
    seen.withLock { $0.append(url) }
    let body = pages.withLock { $0.isEmpty ? #"{"logs": []}"# : $0.removeFirst() }
    guard
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else { throw URLError(.badServerResponse) }
    return (Data(body.utf8), response)
  }

  // swiftlint:disable:next async_without_await
  func stream(for _: URLRequest) async throws -> (
    AsyncThrowingStream<Data, any Error>, HTTPURLResponse
  ) {
    throw URLError(.unsupportedURL)
  }
}

/// A FlySto log page with one log of ``flight(_:flightKey:isLocked:times:in:)``'s flight.
func logPage(id: String, timestamp: String) -> String {
  """
  {
    "logs": [{
      "id": "\(id)", "date": "12 Oct 2026", "aircraft": "N111AA", "from": "KSQL", "to": "KRHV",
      "parameters": [
        { "name": "Brakes off", "value": "2026-10-12T14:10:00Z" },
        { "name": "Takeoff time", "value": "2026-10-12T14:22:00Z" },
        { "name": "Landing time", "value": "2026-10-12T15:08:00Z" },
        { "name": "Brakes on", "value": "2026-10-12T15:25:00Z" }
      ]
    }],
    "timestamp": "\(timestamp)"
  }
  """
}
