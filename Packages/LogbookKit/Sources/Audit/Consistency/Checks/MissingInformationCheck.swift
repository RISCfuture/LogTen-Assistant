import Foundation
import LogbookModel

/**
 Flags entries that lack information a logbook normally holds: total time, an aircraft and its
 type, and the From and To places.

 An entry with no aircraft isn't also reported for its missing type. A simulator session isn't
 asked for total time, landings or places, since its time is checked as simulator time, and an
 entry logging ground time isn't asked for total time. When only one of From and To is set,
 the finding offers copying it to the other, since a flight that returns to its departure still
 records that place as its arrival.
 */
struct MissingInformationCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] {
    [
      .landingsWithoutTime, .missingTotalTime, .missingAircraftType, .missingFromTo,
      .missingAircraft
    ]
  }

  /// Whether an entry dated before today logs no total time, takeoffs, landings or ground time.
  static func lacksTotalTime(_ flight: AuditedFlight, asOf: Date, calendar: Calendar) -> Bool {
    let counts = flight.flight.counts
    return flight.flight.times.total == 0 && flight.flight.times.ground == 0
      && counts.takeoffs + counts.landings == 0
      && calendar.startOfDay(for: flight.flight.date) < calendar.startOfDay(for: asOf)
  }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      checkLandings(flight, &collector)
      checkTotalTime(flight, context, &collector)
      guard flight.flight.times.total > 0 else { continue }
      checkAircraft(flight, &collector)
      checkAircraftType(flight, &collector)
      checkPlaces(flight, &collector)
    }
  }

  private func checkLandings(_ flight: AuditedFlight, _ collector: inout FindingCollector) {
    let counts = flight.flight.counts
    guard !flight.isSimulator, flight.flight.times.total == 0, counts.takeoffs + counts.landings > 0
    else { return }
    collector.emit(
      .landingsWithoutTime,
      [flight.id],
      message: String(
        localized: "Takeoffs or landings are logged without total time.",
        bundle: .module
      ),
      evidence: [
        "takeoffs": .integer(Int(counts.takeoffs)), "landings": .integer(Int(counts.landings)),
        "totaltime": flight["totaltime"].evidenceJSON
      ],
      severity: .questionable,
      explanation: String(
        localized:
          "A takeoff or landing happens during a flight, so an entry that counts them is expected to log how long the flight lasted.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Enter the flight’s total time. If the counts belong to a different entry, move them there.",
        bundle: .module
      )
    )
  }

  private func checkTotalTime(
    _ flight: AuditedFlight,
    _ context: ConsistencyContext,
    _ collector: inout FindingCollector
  ) {
    guard !flight.isSimulator,
      Self.lacksTotalTime(flight, asOf: context.asOf, calendar: context.calendar)
    else { return }
    let seats = SeatAccounting(flight)
    collector.emit(
      .missingTotalTime,
      [flight.id],
      message: missingTotalMessage(seats),
      evidence: ["totaltime": flight["totaltime"].evidenceJSON, "date": dateEvidence(flight)],
      severity: .discrepancy,
      explanation: String(
        localized:
          "A completed flight is expected to log its total time or its takeoffs and landings. Without them it adds nothing to totals and currency.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Enter the flight’s actual duration and review any role times against it. Where two fields describe the same period, that period belongs only once in total time.",
        bundle: .module
      )
    )
  }

  private func missingTotalMessage(_ seats: SeatAccounting) -> String {
    guard !seats.isEmpty else {
      return String(localized: "The flight logs no total time.", bundle: .module)
    }
    let logged = seats.loggedRoles.map {
      String(localized: "\($0.title) \(FlightTimeText.hours(seats.minutes($0)))", bundle: .module)
    }
    return String(
      localized: "\(FlightTimeText.list(logged)) are logged, but the flight adds no total time.",
      bundle: .module
    )
  }

  private func dateEvidence(_ flight: AuditedFlight) -> JSONValue {
    .string(PythonTimestamp.isoformat(flight.flight.date))
  }

  private func checkAircraft(_ flight: AuditedFlight, _ collector: inout FindingCollector) {
    guard flight.flight.aircraft == nil else { return }
    collector.emit(
      .missingAircraft,
      [flight.id],
      message: String(localized: "The flight has no aircraft.", bundle: .module),
      evidence: ["totaltime": flight["totaltime"].evidenceJSON],
      severity: .questionable,
      explanation: String(
        localized:
          "Entries that log time are expected to name the aircraft, so reports can total time by aircraft, type, category and class.",
        bundle: .module
      ),
      recommendation: String(
        localized: "Choose the aircraft flown. If it isn’t in the logbook yet, add it first.",
        bundle: .module
      )
    )
  }

  private func checkAircraftType(_ flight: AuditedFlight, _ collector: inout FindingCollector) {
    guard let aircraft = flight.flight.aircraft, aircraft.type == nil else { return }
    collector.emit(
      .missingAircraftType,
      [flight.id],
      message: String(localized: "The aircraft has no aircraft type.", bundle: .module),
      evidence: [
        "aircraft": .string(aircraft.registration), "totaltime": flight["totaltime"].evidenceJSON
      ],
      explanation: String(
        localized:
          "Time in an aircraft with no type can’t be totaled by type, category or class, which currency and experience requirements depend on.",
        bundle: .module
      ),
      recommendation: String(
        localized: "Give the aircraft its type in the Aircraft list.",
        bundle: .module
      )
    )
  }

  private func checkPlaces(_ flight: AuditedFlight, _ collector: inout FindingCollector) {
    let (from, to) = (flight.flight.from, flight.flight.to)
    guard !flight.isSimulator, from == nil || to == nil else { return }
    collector.emit(
      .missingFromTo,
      [flight.id],
      message: placesMessage(from: from, to: to),
      evidence: [
        "from": from.map { .string($0.preferredIdentifier) } ?? .null,
        "to": to.map { .string($0.preferredIdentifier) } ?? .null
      ],
      explanation: String(
        localized:
          "From and To are expected on every flight so its departure and arrival appear in the logbook and reports. Route holds the airports in between. A flight that returns to its departure still needs that place in To.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "If you returned to the departure place, copy it across. Otherwise enter the actual place.",
        bundle: .module
      ),
      corrections: matchingOptions(flight, from: from, to: to)
    )
  }

  private func placesMessage(from: Place?, to: Place?) -> String {
    switch (from, to) {
      case (.some, nil): String(localized: "From is logged, but To is empty.", bundle: .module)
      case (nil, .some): String(localized: "To is logged, but From is empty.", bundle: .module)
      default: String(localized: "From and To are both empty.", bundle: .module)
    }
  }

  private func matchingOptions(
    _ flight: AuditedFlight,
    from: Place?,
    to: Place?
  ) -> [CorrectionOption] {
    switch (from, to) {
      case (let from?, nil):
        [
          option(
            flight,
            title: String(localized: "Set To to Match From", bundle: .module),
            detail: { String(localized: "To becomes “\($0)”.", bundle: .module) },
            field: .flightTo,
            place: from
          )
        ]
      case (nil, let to?):
        [
          option(
            flight,
            title: String(localized: "Set From to Match To", bundle: .module),
            detail: { String(localized: "From becomes “\($0)”.", bundle: .module) },
            field: .flightFrom,
            place: to
          )
        ]
      default: []
    }
  }

  private func option(
    _ flight: AuditedFlight,
    title: String,
    detail: (String) -> String,
    field: LogTenFieldKey,
    place: Place
  ) -> CorrectionOption {
    let identifier = place.preferredIdentifier
    return CorrectionOption(
      title: title,
      detail: detail(identifier),
      changes: [flight.change(field, to: .text(identifier))]
    )
  }
}
