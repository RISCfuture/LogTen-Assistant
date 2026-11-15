import Foundation
import LogbookModel

/// Flags dual given or received whose instructor and student names are missing, where the
/// pilot usually names them, or contradict the pilot’s own role.
struct InstructionNamesCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.instructionNames] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let namesStudent = FlightHabit(
      over: context.flights,
      similarity: .aircraftType,
      when: { $0.hasPositive("dualgiven") },
      records: { $0.flight.crew.student != nil }
    )
    let namesInstructor = FlightHabit(
      over: context.flights,
      similarity: .aircraftType,
      when: { $0.hasPositive("dualreceived") },
      records: { $0.flight.crew.instructor != nil }
    )
    let owner = context.settings.pilot.ownerPersonID
    for flight in context.flights {
      var problems = Problem.conflicts(in: flight, owner: owner)
      if flight.hasPositive("dualgiven"), flight.flight.crew.student == nil,
        namesStudent.isUsual(for: flight)
      {
        problems.append(.studentMissing)
      }
      if flight.hasPositive("dualreceived"), flight.flight.crew.instructor == nil,
        namesInstructor.isUsual(for: flight)
      {
        problems.append(.instructorMissing)
      }
      guard let first = problems.first else { continue }
      collector.emit(
        .instructionNames,
        [flight.id],
        message: first.message,
        evidence: [
          "problems": .array(problems.map { .string($0.rawValue) }),
          "dualgiven": flight["dualgiven"].evidenceJSON,
          "dualreceived": flight["dualreceived"].evidenceJSON
        ],
        severity: problems.contains(where: \.isConflict) ? .questionable : .suggestion,
        explanation: String(
          localized:
            "The instructor and student names say who gave and who received the instruction in dual time. Entries that omit them, or name you on the wrong side, leave the record of the training incomplete.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Add or correct the name in the crew, or correct the dual time if it was entered in error. If the entry is intentional, keep it as logged.",
          bundle: .module
        )
      )
    }
  }

  private enum Problem: String {
    case ownerIsInstructorOfDualReceived = "owner_is_instructor_of_dual_received"
    case ownerIsStudentOfDualGiven = "owner_is_student_of_dual_given"
    case studentMissing = "student_missing"
    case instructorMissing = "instructor_missing"

    var isConflict: Bool { self != .studentMissing && self != .instructorMissing }

    var message: String {
      switch self {
        case .studentMissing:
          String(localized: "Dual given is logged, but no student is named.", bundle: .module)
        case .instructorMissing:
          String(localized: "Dual received is logged, but no instructor is named.", bundle: .module)
        case .ownerIsInstructorOfDualReceived:
          String(
            localized: "Dual received is logged, but you’re named as the instructor.",
            bundle: .module
          )
        case .ownerIsStudentOfDualGiven:
          String(
            localized: "Dual given is logged, but you’re named as the student.",
            bundle: .module
          )
      }
    }

    static func conflicts(in flight: AuditedFlight, owner: RecordID?) -> [Self] {
      guard let owner else { return [] }
      let crew = flight.flight.crew
      var problems = [Self]()
      if flight.hasPositive("dualreceived"), crew.instructor?.id == owner {
        problems.append(.ownerIsInstructorOfDualReceived)
      }
      if flight.hasPositive("dualgiven"), crew.student?.id == owner {
        problems.append(.ownerIsStudentOfDualGiven)
      }
      return problems
    }
  }
}
