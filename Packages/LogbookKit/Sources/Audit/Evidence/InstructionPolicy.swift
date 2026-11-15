import Foundation
public import LogbookModel

/// A finding the instruction-activity policy removed from the report, with the reason.
public struct ExcludedFinding: Hashable, Sendable {
  /// The finding, with its evidence intact so a decision about it can still be carried forward.
  public var finding: Finding
  /// The policy that excluded it.
  public var policy: String
  /// Why the policy applies.
  public var reason: String
}

/// The policy that ignores student-attributable activity on instructional flights.
///
/// When the logbook owner instructs, or someone else is listed as the student, the student
/// flies the takeoffs, landings and approaches, and the instructor isn't credited with them.
/// Comparisons of those counts, personal approach context and credited time shorter than the
/// block interval are excluded. Aircraft timestamps and impossible combinations of credited
/// values stay in review. Training received and instruction time alone don't trigger the policy.
public enum InstructionPolicy {
  /// The policy's name, as recorded on excluded findings.
  public static let name = "ignore_instruction_activity"

  private static let studentActivityRules: Set<RuleID> = [
    "telemetry_count", "telemetry_approach_candidates", "approach_without_instrument_context",
    "approach_quantity_missing"
  ]

  private static func isStudentActivity(_ finding: Finding) -> Bool {
    if studentActivityRules.contains(finding.rule) { return true }
    switch finding.rule {
      case "telemetry_source_conflict":
        return finding.evidence["kind"]?.stringValue == "count"
      case "block_duration":
        guard let logged = finding.evidence["logged_minutes"]?.doubleValue,
          let elapsed = finding.evidence["elapsed_minutes"]?.doubleValue
        else { return false }
        return logged >= 0 && logged < elapsed
      default:
        return false
    }
  }

  /**
   Finds the entries where the owner instructs or another person is the student.

   - Parameters:
     - flights: The logbook entries.
     - owner: The person whose logbook it is.
   - Throws: ``EvidenceError/ownerNotIdentified`` if there is no owner.
   */
  public static func instructionalFlightIDs(in flights: [Flight], owner: RecordID?) throws -> Set<
    RecordID
  > {
    guard let owner else { throw EvidenceError.ownerNotIdentified }
    return Set(
      flights.filter {
        $0.crew.instructor?.id == owner || ($0.crew.student != nil && $0.crew.student?.id != owner)
      }
      .map(\.id)
    )
  }

  /**
   Separates the findings the policy excludes from those that remain.

   - Parameters:
     - findings: The findings to filter.
     - instructional: The entries from ``instructionalFlightIDs(in:owner:)``.
   */
  public static func suppress(_ findings: [Finding], instructional: Set<RecordID>) -> (
    retained: [Finding], excluded: [ExcludedFinding]
  ) {
    var retained = [Finding]()
    var excluded = [ExcludedFinding]()
    for finding in findings {
      if isStudentActivity(finding), finding.recordIDs.count == 1,
        instructional.contains(finding.recordIDs[0])
      {
        excluded.append(
          ExcludedFinding(
            finding: finding,
            policy: name,
            reason: String(
              localized:
                "The logbook owner is listed as Instructor or another person is listed as Student; the student may perform events or receive flight time that the owner does not log as personal credit.",
              bundle: .module
            )
          )
        )
      } else {
        retained.append(finding)
      }
    }
    return (retained, excluded)
  }
}
