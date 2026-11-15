import Foundation
import LogbookModel

/**
 One check of the consistency audit, reporting the findings of one or more
 ``ConsistencyRule``s.

 A check reads the logbook through a ``ConsistencyContext`` and adds its findings, and any
 analyses of them, to a ``FindingCollector``. The audit runs a check only when one of its
 ``rules`` is enabled, and drops the findings of any rule that isn't. Checks are listed in
 ``ConsistencyCheckRegistry/checks``; one that reads another's findings is listed after it.
 */
protocol ConsistencyCheck: Sendable {
  /// The rules whose findings the check reports.
  var rules: [ConsistencyRule] { get }

  /// Adds the check's findings over a logbook to a collector.
  func check(_ context: ConsistencyContext, into collector: inout FindingCollector)
}

/// What a ``ConsistencyCheck`` reads: the logbook, its flights as the rules see them, the
/// settings and options, and the date the audit is run as of.
struct ConsistencyContext {
  /// The logbook snapshot.
  let logbook: Logbook

  /// Every flight of the logbook, in logbook order.
  let flights: [AuditedFlight]

  /// The logbook's settings.
  let settings: LogbookSettings

  /// The audit's options.
  let options: ConsistencyAuditOptions

  /// The date the audit is run as of, which decides what is in the future.
  let asOf: Date

  /// Which fields hold the roles the checks need.
  var mapping: FieldMapping { settings.fieldMapping }

  /// The matching and plausibility tolerances.
  var tolerances: AuditTolerances { settings.rules.tolerances }

  /// A Gregorian calendar in the pilot's home time zone, for reckoning calendar days.
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = settings.pilot.homeTimeZone
    return calendar
  }

  init(
    logbook: Logbook,
    settings: LogbookSettings,
    options: ConsistencyAuditOptions,
    asOf: Date
  ) {
    self.logbook = logbook
    flights = logbook.flights.map(AuditedFlight.init)
    self.settings = settings
    self.options = options
    self.asOf = asOf
  }

  /// The longest plausible flight in an entry's aircraft, in minutes.
  func maximumMinutes(for flight: AuditedFlight) -> UInt {
    flight.registration.flatMap { settings.aircraft[$0]?.maximumFlightTime }
      ?? tolerances.maximumFlightMinutes
  }

  /// The title LogTen shows for one of a flight's attributes, by its lowercased name.
  func title(of name: String, in flight: AuditedFlight) -> String {
    flight.keys[name].map(logbook.title) ?? FieldTitle.title(ofAttribute: name) ?? name
  }
}
