import Foundation
import LogbookModel

/**
 Flags night role times that don't fit a flight's night time or their own role's time.

 Night role times share night time the way role times share total time, as ``SeatAccounting``
 describes. When the only fault is a night role time above its role's time, the finding offers
 limiting those night times to their roles' times.
 */
struct NightSeatTimeCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.nightSeatTime] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights where !flight.isSimulator {
      let nights = SeatAccounting(nightOf: flight)
      guard !nights.isEmpty else { continue }
      let night = flight.flight.times.night
      let overRole = SeatRole.allCases.filter { nights.minutes($0) > roleMinutes(flight, $0) }
      let exceedsNight = nights.occupied > night
      guard !overRole.isEmpty || exceedsNight else { continue }
      collector.emit(
        .nightSeatTime,
        [flight.id],
        message: String(localized: "Night seat times need review.", bundle: .module),
        evidence: evidence(flight, nights, night: night),
        severity: .discrepancy,
        explanation: explanation(night: night, overRole: overRole, exceedsNight: exceedsNight),
        recommendation: String(
          localized:
            "Correct the night role time or the role time it belongs to. If night time itself is understated, correct that instead.",
          bundle: .module
        ),
        corrections: limitingOptions(flight, nights, night: night, overRole: overRole)
      )
    }
  }

  private func roleMinutes(_ flight: AuditedFlight, _ role: SeatRole) -> UInt {
    UInt(max(0, flight.number(role.attribute) ?? 0))
  }

  private func evidence(
    _ flight: AuditedFlight,
    _ nights: SeatAccounting,
    night: UInt
  ) -> JSONValue {
    var evidence = [String: JSONValue]()
    for role in SeatRole.allCases where nights.minutes(role) > 0 {
      evidence[role.nightAttribute] = .integer(Int(nights.minutes(role)))
      evidence[role.attribute] = .integer(Int(roleMinutes(flight, role)))
    }
    evidence["night"] = .integer(Int(night))
    return .object(evidence)
  }

  private func explanation(night: UInt, overRole: [SeatRole], exceedsNight: Bool) -> String {
    if let role = overRole.first, !exceedsNight {
      return String(
        localized:
          "\(role.nightTitle) is part of \(role.title), so it can’t be longer than the \(role.title) time on the same flight.",
        bundle: .module
      )
    }
    return String(
      localized:
        "Night role times are parts of the flight’s night time of \(FlightTimeText.hours(night)). Roles that can’t share a period, such as PIC and SIC, can’t together be longer than it.",
      bundle: .module
    )
  }

  private func limitingOptions(
    _ flight: AuditedFlight,
    _ nights: SeatAccounting,
    night: UInt,
    overRole: [SeatRole]
  ) -> [CorrectionOption] {
    let limited = nights.limited { roleMinutes(flight, $0) }
    guard !overRole.isEmpty, limited.occupied <= night else { return [] }
    let changes = overRole.map { role in
      flight.change(
        AuditedFlight.fieldKey(role.nightFieldName),
        to: .integer(Int(roleMinutes(flight, role)))
      )
    }
    return [
      CorrectionOption(
        title: String(localized: "Limit Night Role Times", bundle: .module),
        detail: String(
          localized:
            "\(FlightTimeText.list(overRole.map(\.nightTitle))) become no longer than the matching role time.",
          bundle: .module
        ),
        changes: changes
      )
    ]
  }
}
