import Foundation
import LogbookModel

/// Flags solo time on an entry that names an instructor.
struct SoloWithInstructorCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.soloWithInstructor] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights where flight.hasPositive("solo") {
      guard let instructor = flight.flight.crew.instructor else { continue }
      collector.emit(
        .soloWithInstructor,
        [flight.id],
        message: String(
          localized: "Solo time is logged, but an instructor is named.",
          bundle: .module
        ),
        evidence: [
          "solo": flight["solo"].evidenceJSON,
          "instructor": .string(instructor.id.rawValue)
        ],
        severity: .questionable,
        explanation: String(
          localized:
            "Solo time means no one else was aboard to give instruction, so an instructor named on the same entry contradicts it.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Remove the instructor if the flight was solo, or correct the solo time if the instructor flew with you. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }
}
