import Foundation
import LogbookModel

/**
 Flags role times that don't fit a flight's total time, and total time the roles don't account
 for.

 The check counts the minutes the roles occupy as ``SeatAccounting`` describes, so a PIC who
 also logs dual received for the same period isn't flagged, while PIC and SIC that each fill
 the flight are. When the roles overbook the flight and only PIC and SIC are involved, the
 finding offers clearing either one, together with its night time, as alternatives. Total time
 the roles leave uncovered is flagged however small the gap. A role, solo or dual given that
 alone exceeds total time is left to the time-consistency rule. Entries with no total time are
 left to the missing-total rule unless they log landings, which that rule accepts.
 */
struct SeatTimeCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.seatTime] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights where !flight.isSimulator {
      let seats = SeatAccounting(flight)
      let total = flight.flight.times.total
      if total == 0 {
        checkMissingTotal(of: flight, seats, into: &collector)
      } else if seats.commandLevel <= total,
        SeatRole.allCases.allSatisfy({ seats.minutes($0) <= total })
      {
        if seats.occupied > total {
          reportOverbooked(flight, seats, total: total, into: &collector)
        } else if seats.occupied < total {
          reportUnaccounted(flight, seats, total: total, into: &collector)
        }
      }
    }
  }

  private func checkMissingTotal(
    of flight: AuditedFlight,
    _ seats: SeatAccounting,
    into collector: inout FindingCollector
  ) {
    let counts = flight.flight.counts
    guard !seats.isEmpty, counts.takeoffs + counts.landings > 0 else { return }
    collector.emit(
      .seatTime,
      [flight.id],
      message: String(localized: "Total time is missing.", bundle: .module),
      evidence: ["roles": roleEvidence(seats), "totaltime": .null],
      severity: .discrepancy,
      explanation: String(
        localized:
          "Role times describe parts of a flight’s total time, so a flight that logs them needs a total to measure them against.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Enter the flight’s total time, then review the role times against it. Where two roles describe the same period, that period belongs only once in the total.",
        bundle: .module
      )
    )
  }

  private func reportOverbooked(
    _ flight: AuditedFlight,
    _ seats: SeatAccounting,
    total: UInt,
    into collector: inout FindingCollector
  ) {
    let logged = seats.loggedRoles.map {
      String(localized: "\($0.title) \(FlightTimeText.hours(seats.minutes($0)))", bundle: .module)
    }
    collector.emit(
      .seatTime,
      [flight.id],
      message: String(
        localized:
          "\(FlightTimeText.list(logged)) are logged. The role times exceed total time \(FlightTimeText.hours(total)) by \(FlightTimeText.span(seats.occupied - total)).",
        bundle: .module
      ),
      evidence: ["roles": roleEvidence(seats), "totaltime": .integer(Int(total))],
      severity: .discrepancy,
      explanation: overbookedExplanation(seats, logged: logged, total: total),
      recommendation: String(
        localized:
          "Clear a role entered in error when a correction is offered. If both roles are intentional, correct their separate durations or an understated total time. Check Crew as well if its listed position isn’t the one you meant to record.",
        bundle: .module
      ),
      corrections: clearingOptions(flight, seats, total: total)
    )
  }

  private func overbookedExplanation(
    _ seats: SeatAccounting,
    logged: [String],
    total: UInt
  ) -> String {
    guard seats.loggedRoles.contains(.pic), seats.loggedRoles.contains(.sic) else {
      return String(
        localized:
          "\(FlightTimeText.list(logged)) can’t share the same minutes, so together they have to fit within total time \(FlightTimeText.hours(total)).",
        bundle: .module
      )
    }
    return String(
      localized:
        "PIC and SIC aren’t normally expected on the same flight. If one entry holds separate periods in those roles, their durations still have to fit within total time.",
      bundle: .module
    )
  }

  private func reportUnaccounted(
    _ flight: AuditedFlight,
    _ seats: SeatAccounting,
    total: UInt,
    into collector: inout FindingCollector
  ) {
    collector.emit(
      .seatTime,
      [flight.id],
      message: String(
        localized: "Total time is not fully accounted for by role.",
        bundle: .module
      ),
      evidence: ["roles": roleEvidence(seats), "totaltime": .integer(Int(total))],
      severity: .questionable,
      explanation: unaccountedExplanation(seats, total: total),
      recommendation: String(
        localized:
          "Add the role that covers the rest of the flight, such as PIC or dual received, or correct the total if it was entered in error. If the flight is intentionally logged without a role, keep it as logged.",
        bundle: .module
      )
    )
  }

  private func unaccountedExplanation(_ seats: SeatAccounting, total: UInt) -> String {
    guard seats.occupied > 0 else {
      return String(
        localized:
          "No role time is logged, so none of the \(FlightTimeText.span(total)) of total time has a role.",
        bundle: .module
      )
    }
    return String(
      localized:
        "Total time of \(FlightTimeText.span(total)) includes \(FlightTimeText.span(total - seats.occupied)) that no role time covers, so that part of the flight has no role.",
      bundle: .module
    )
  }

  /// Options that clear PIC or SIC, offered when only those two are logged and clearing either
  /// one makes the flight fit.
  private func clearingOptions(
    _ flight: AuditedFlight,
    _ seats: SeatAccounting,
    total: UInt
  ) -> [CorrectionOption] {
    guard seats.loggedRoles.contains(.pic), seats.loggedRoles.contains(.sic),
      !seats.loggedRoles.contains(.p1us)
    else { return [] }
    return [(SeatRole.sic, SeatRole.pic), (.pic, .sic)].compactMap { cleared, kept in
      guard seats.removing(cleared).occupied <= total else { return nil }
      return clearingOption(flight, seats, clearing: cleared, keeping: kept)
    }
  }

  private func clearingOption(
    _ flight: AuditedFlight,
    _ seats: SeatAccounting,
    clearing role: SeatRole,
    keeping kept: SeatRole
  ) -> CorrectionOption {
    let changes = flight.clearing([role.fieldName, role.nightFieldName])
    let cleared =
      [role.title + " " + FlightTimeText.hours(seats.minutes(role))]
      + changes.dropFirst().map { _ in
        role.nightTitle + " " + FlightTimeText.hours(flight.nightMinutes(of: role))
      }
    return CorrectionOption(
      title: String(localized: "Clear \(role.title)", bundle: .module),
      detail: String(
        localized:
          "Cleared: \(FlightTimeText.list(cleared)). \(kept.title) stays at \(FlightTimeText.hours(seats.minutes(kept))).",
        bundle: .module
      ),
      changes: changes
    )
  }

  private func roleEvidence(_ seats: SeatAccounting) -> JSONValue {
    .object(
      Dictionary(
        uniqueKeysWithValues: SeatRole.allCases.map {
          ($0.attribute, .integer(Int(seats.minutes($0))))
        }
      )
    )
  }
}

extension AuditedFlight {
  /// The minutes a role logs as night time.
  func nightMinutes(of role: SeatRole) -> UInt {
    UInt(max(0, number(role.nightAttribute) ?? 0))
  }
}
