import Audit
import FlightSources
import Foundation
import LogbookModel
import Tracks

/// What a flight's sources recorded for a value on which the audit found the logbook disagrees.
nonisolated struct SourceDiscrepancy: Hashable {
  /// The compared value's name, such as “Takeoff” or “Landings”.
  let title: String

  /// The flight details that show the value, the most fitting first.
  let fields: [LogTenFieldKey]

  /// What the logbook records.
  let logbookValue: String

  /// What each source recorded, in the order the audit consulted them.
  let readings: [Reading]

  /// One source's value.
  struct Reading: Hashable {
    /// The source's name.
    let source: String

    /// The recorded value, or “—” when the source doesn't know it.
    let value: String

    /// Whether the audit compared this source's value with the logbook's.
    let isPreferred: Bool

    /// Whether the audit could use the value.
    let isUsable: Bool

    /// Whether the source's own repeated records disagree.
    let hasConflict: Bool
  }
}

nonisolated extension SourceDiscrepancy {
  /// The discrepancy a comparison found, or `nil` when the preferred source agrees with the
  /// logbook or no source was usable.
  init?(_ choice: SourceChoice, flight: Flight) {
    guard let selected = choice.selected, !choice.agrees else { return nil }
    self.init(
      title: choice.field.title,
      fields: choice.field.detailFields,
      logbookValue: SourceValue.logbook(flight, choice.field),
      readings: choice.observations.map { observation in
        Reading(
          source: observation.source.title,
          value: SourceValue.text(of: observation),
          isPreferred: observation.source == selected,
          isUsable: observation.isUsable,
          hasConflict: observation.hasConflict
        )
      }
    )
  }
}

nonisolated extension ObservedField {
  /// The flight details that show the field: a time's own detail, or the day and night details
  /// a count is the sum of.
  fileprivate var detailFields: [LogTenFieldKey] {
    switch self {
      case .time(.out): [.flightActualDepartureTime]
      case .time(.takeoff): [.flightTakeoffTime]
      case .time(.landing): [.flightLandingTime]
      case .time(.in): [.flightActualArrivalTime]
      case .time(.startup), .time(.shutdown): []
      case .count(.takeoff): [.flightDayTakeoffs, .flightNightTakeoffs]
      case .count(.landing): [.flightDayLandings, .flightNightLandings]
      case .count(.fullStop): [.flightFullStops]
    }
  }
}

/// Formats the values a source comparison shows.
nonisolated enum SourceValue {
  /// A source's observed value: a Zulu time or a count, or “—” when unknown.
  static func text(of observation: SourceObservation?) -> String {
    switch observation?.value {
      case .string(let text):
        (try? Date(text, strategy: .iso8601)).map(LogbookFormat.zuluTime) ?? text
      case .integer(let count): count.formatted(.number)
      case .double(let number): number.formatted(.number.precision(.fractionLength(0...1)))
      default: String(localized: "—")
    }
  }

  /// What the logbook records for a compared field.
  static func logbook(_ flight: Flight, _ field: ObservedField) -> String {
    switch field {
      case .time(let kind):
        time(of: flight, kind).map(LogbookFormat.zuluTime) ?? String(localized: "—")
      case .count(.takeoff): flight.counts.takeoffs.formatted(.number)
      case .count(.landing): flight.counts.landings.formatted(.number)
      case .count(.fullStop): flight.counts.fullStops.formatted(.number)
    }
  }

  private static func time(of flight: Flight, _ kind: FlyStoTimeKind) -> Date? {
    switch kind {
      case .out: flight.events.out
      case .takeoff: flight.events.off
      case .landing: flight.events.on
      case .in: flight.events.in
      case .startup, .shutdown: nil
    }
  }
}
