public import FlightSources
import Foundation
public import LogbookModel

/// How a piece of external evidence was assigned to a logbook entry.
public struct EvidenceMatch: Hashable, Sendable {
  /// The `FlyStoRecord.id` of the evidence.
  public var sourceID: String

  /// The selected entry, if the match is unique.
  public var flightID: RecordID?
  /// The outcome.
  public var status: Status

  /// Every entry that fit, best first.
  public var candidates: [Candidate]

  /// What the match rests on.
  public var basis: Basis

  /// The candidate for the selected entry.
  public var selected: Candidate? { candidates.first { $0.flightID == flightID } }

  /// The outcome of matching.
  public enum Status: String, Codable, Sendable {
    /// Exactly one entry was selected.
    case matched
    /// Several entries fit and none stands out, or two sources claim the same entry.
    case ambiguous
    /// No entry fits.
    case unmatched
  }

  /// How a record was matched.
  public enum Basis: String, Codable, Sendable {
    /// The aircraft, the airports, the date and the clock times.
    case aircraftRouteAndTime = "aircraft_route_and_time"
    /// The aircraft and at least two UTC times, independent of the airports.
    case twoUTCAnchors = "two_utc_anchors"
  }

  /// An entry that could be the one the evidence describes.
  public struct Candidate: Hashable, Sendable {
    /// The entry.
    public var flightID: RecordID
    /// The median difference between the record's and the entry's times, in minutes; `nil` when
    /// the match rests on the date and route alone.
    public var distanceMinutes: Double?
    /// The largest difference between any pair of times, in minutes.
    public var maximumDeltaMinutes: Double?
    /// How many times the record and the entry have in common.
    public var anchors: Int
    /// Whether the match rests on the date and route alone.
    public var isDateOnly: Bool
  }
}

/// Assigns FlySto records to logbook entries, a port of cleanup-logten's
/// `flysto.match_exports` and `evidence.match_by_time`.
public struct EvidenceMatcher: Sendable {
  private static let maximumClockOffsetMinutes = 90.0
  private static let separationMinutes = 20.0
  private static let timeSeparationMinutes = 5.0
  private static let unrankedDistance = 999.0
  private static let secondsPerDay = 86_400.0
  private static let secondsPerMinute = 60.0

  private let identity: AircraftIdentity

  /// Creates a matcher.
  ///
  /// - Parameter aircraft: Per-aircraft settings keyed by registration, whose aliases let a
  ///   record and an entry name the same aircraft differently.
  public init(aircraft: [String: AircraftSettings] = [:]) {
    identity = AircraftIdentity(settings: aircraft)
  }

  private static func selection(among candidates: [EvidenceMatch.Candidate]) -> RecordID? {
    guard let best = candidates.first else { return nil }
    if candidates.count == 1 { return best.flightID }
    guard let bestDistance = best.distanceMinutes,
      let nextDistance = candidates[1].distanceMinutes,
      nextDistance - bestDistance >= separationMinutes
    else { return nil }
    return best.flightID
  }

  /**
   Matches records by aircraft, route, date and clock times.

   An entry is a candidate when the aircraft agrees, no airport disagrees, the dates are within
   a day, and some time is within 90 minutes (or, if neither side has times, the date and both
   airports agree). A candidate is selected when it is the only one, or when it beats the next
   by 20 minutes. If two records select the same entry, both become ambiguous.

   - Parameters:
     - records: The FlySto records; ground activity and incomplete records are skipped.
     - flights: The logbook entries.
   */
  public func matchExports(_ records: [FlyStoRecord], to flights: [Flight]) -> [EvidenceMatch] {
    var matches = records.filter(\.isFlight).map { record -> EvidenceMatch in
      let candidates = flights.compactMap { candidate(for: record, flight: $0) }
        .sorted {
          ($0.distanceMinutes ?? Self.unrankedDistance, $0.flightID) < (
            $1.distanceMinutes ?? Self.unrankedDistance, $1.flightID
          )
        }
      let selected = Self.selection(among: candidates)
      return EvidenceMatch(
        sourceID: record.id,
        flightID: selected,
        status: selected != nil ? .matched : candidates.isEmpty ? .unmatched : .ambiguous,
        candidates: candidates,
        basis: .aircraftRouteAndTime
      )
    }
    let claims = Dictionary(grouping: matches.indices.filter { matches[$0].flightID != nil }) {
      matches[$0].flightID!
    }
    for indices in claims.values where indices.count > 1 {
      for index in indices {
        matches[index].flightID = nil
        matches[index].status = .ambiguous
      }
    }
    return matches
  }

  private func candidate(for record: FlyStoRecord, flight: Flight) -> EvidenceMatch.Candidate? {
    guard identity.isSame(record.registration, flight.aircraft?.registration),
      !routeDisagrees(record, flight),
      abs(record.day.timeIntervalSince(flight.utcDay)) <= Self.secondsPerDay
    else { return nil }
    let deltas = timeDeltas(record, flight)
    guard let smallest = deltas.min() else {
      guard isRouteComplete(record, flight), record.day == flight.utcDay else { return nil }
      return .init(
        flightID: flight.id,
        distanceMinutes: nil,
        maximumDeltaMinutes: nil,
        anchors: 0,
        isDateOnly: true
      )
    }
    guard smallest <= Self.maximumClockOffsetMinutes else { return nil }
    return .init(
      flightID: flight.id,
      distanceMinutes: deltas.median,
      maximumDeltaMinutes: deltas.max(),
      anchors: deltas.count,
      isDateOnly: false
    )
  }

  private func routeDisagrees(_ record: FlyStoRecord, _ flight: Flight) -> Bool {
    [(record.from, flight.from), (record.to, flight.to)].contains { recorded, logged in
      guard let recorded, !recorded.isEmpty, let logged else { return false }
      return !logged.identifierKeys.contains(airportKey(recorded))
    }
  }

  private func isRouteComplete(_ record: FlyStoRecord, _ flight: Flight) -> Bool {
    [record.from, record.to].allSatisfy { !($0 ?? "").isEmpty } && flight.from != nil
      && flight.to != nil
  }

  /**
   Matches records by aircraft and at least two UTC times, ignoring the airports.

   This catches entries with a wrong or missing route. A record with untrustworthy clock times
   never matches, and simulators are skipped. A candidate is selected when it is the only one
   or beats the next by five minutes.

   - Parameters:
     - records: The FlySto records.
     - flights: The logbook entries.
     - toleranceMinutes: How far any pair of times may differ.
   */
  public func matchByTime(
    _ records: [FlyStoRecord],
    to flights: [Flight],
    toleranceMinutes: Double = 15
  ) -> [EvidenceMatch] {
    records.filter(\.isFlight).map { record in
      var candidates = [EvidenceMatch.Candidate]()
      if record.timeIssues.isEmpty {
        for flight in flights
        where identity.isSame(record.registration, flight.aircraft?.registration)
          && !flight.isSimulation
        {
          let deltas = timeDeltas(record, flight)
          guard deltas.count >= 2, let largest = deltas.max(), largest <= toleranceMinutes else {
            continue
          }
          candidates.append(
            .init(
              flightID: flight.id,
              distanceMinutes: deltas.median,
              maximumDeltaMinutes: largest,
              anchors: deltas.count,
              isDateOnly: false
            )
          )
        }
      }
      candidates.sort {
        ($0.distanceMinutes!, -$0.anchors, $0.flightID) < (
          $1.distanceMinutes!, -$1.anchors, $1.flightID
        )
      }
      let isUnique =
        candidates.count == 1
        || (candidates.count > 1
          && candidates[1].distanceMinutes! - candidates[0].distanceMinutes!
            >= Self.timeSeparationMinutes)
      return EvidenceMatch(
        sourceID: record.id,
        flightID: isUnique ? candidates[0].flightID : nil,
        status: isUnique ? .matched : candidates.isEmpty ? .unmatched : .ambiguous,
        candidates: candidates,
        basis: .twoUTCAnchors
      )
    }
  }

  /// The differences, in minutes, between each time the record and the entry both have.
  private func timeDeltas(_ record: FlyStoRecord, _ flight: Flight) -> [Double] {
    let pairs: [(Date?, Date?)] = [
      (record.times.out, flight.events.out), (record.times.takeoff, flight.events.off),
      (record.times.landing, flight.events.on), (record.times.in, flight.events.in)
    ]
    return pairs.compactMap { recorded, logged in
      guard let recorded, let logged else { return nil }
      return abs(recorded.timeIntervalSince(logged)) / Self.secondsPerMinute
    }
  }
}

extension Flight {
  /// The UTC calendar day of the entry's date, as midnight UTC.
  var utcDay: Date { utcCalendar.startOfDay(for: date) }

  /// Whether the entry is in a simulator or training device.
  var isSimulation: Bool { aircraft?.type?.category?.isSimulationDevice == true }
}

extension Place {
  /// The airport-key spellings of the identifiers the place goes by.
  var identifierKeys: Set<String> {
    Set([ICAO, FAAID, identifier].compactMap(\.self).map(airportKey))
  }
}

extension Array where Element == Double {
  /// The median, averaging the middle pair of an even-length array; `nil` if empty.
  var median: Double? {
    guard !isEmpty else { return nil }
    let sorted = sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }
}

/// A Gregorian calendar fixed to UTC.
let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  return calendar
}()
