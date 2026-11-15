import Foundation
import LogbookModel

/// Flags PIC or SIC time that disagrees with the seat the pilot is listed in under crew.
struct CrewSeatCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.crewSeat] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    guard let owner = context.settings.pilot.ownerPersonID else { return }
    for flight in context.flights {
      guard let mismatch = Mismatch(flight, owner: owner) else { continue }
      collector.emit(
        .crewSeat,
        [flight.id],
        message: mismatch.message,
        evidence: [
          "listed_seat": .string(mismatch.listedSeat),
          "pic": flight["pic"].evidenceJSON,
          "sic": flight["sic"].evidenceJSON
        ],
        severity: .questionable,
        explanation: String(
          localized:
            "The time you logged as pilot in command or second in command should match the seat you’re listed in under crew. When they differ, reports built from either one disagree with the other.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Correct the crew listing if you flew the other seat, or correct the role time if the listing is right. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }

  /// The way a flight's role time contradicts the owner's crew listing.
  private enum Mismatch {
    case picTimeFromSecondSeat
    case sicTimeFromCommandSeat

    var listedSeat: String {
      switch self {
        case .picTimeFromSecondSeat: "sic"
        case .sicTimeFromCommandSeat: "pic"
      }
    }

    var message: String {
      switch self {
        case .picTimeFromSecondSeat:
          String(
            localized: "PIC time is logged, but you’re listed as second in command.",
            bundle: .module
          )
        case .sicTimeFromCommandSeat:
          String(
            localized: "SIC time is logged, but you’re listed as pilot in command.",
            bundle: .module
          )
      }
    }

    init?(_ flight: AuditedFlight, owner: RecordID) {
      let crew = flight.flight.crew
      if flight.hasPositive("pic"), crew.SIC?.id == owner, crew.PIC?.id != owner {
        self = .picTimeFromSecondSeat
      } else if flight.hasPositive("sic"), crew.PIC?.id == owner, crew.SIC?.id != owner {
        self = .sicTimeFromCommandSeat
      } else {
        return nil
      }
    }
  }
}
