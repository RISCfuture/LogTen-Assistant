import Foundation
import LogbookModel

/// Finds pairs of entries on the same date, in the same aircraft, between the same places,
/// that look like one flight logged twice.
struct DuplicateFlightCheck: ConsistencyCheck {
  private static let ignoredNames: Set = [
    "key", "flightcrew", "flightpassengers", "flightapproaches", "signature", "islocked"
  ]
  private static let minimumRemarkSimilarity = 0.88
  private static var lessonPattern: Regex<(Substring, Substring)> {
    /(?:fstd|lesson(?: plan)?(?: flight)?)\s*#?\s*(\d+)/
  }

  var rules: [ConsistencyRule] { [.duplicateExact, .duplicateCandidate] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let tolerances = context.tolerances
    var groups = [GroupKey: [AuditedFlight]]()
    for flight in context.flights.sorted(by: { $0.id < $1.id }) {
      guard let registration = flight.registration else { continue }
      let key = GroupKey(
        date: flight.dateKey,
        registration: registration,
        from: flight.flight.from?.preferredIdentifier,
        to: flight.flight.to?.preferredIdentifier
      )
      groups[key, default: []].append(flight)
    }
    for candidates in groups.values {
      for (index, first) in candidates.enumerated() {
        for second in candidates[(index + 1)...] {
          check(first, second, tolerances: tolerances, into: &collector)
        }
      }
    }
  }

  private func check(
    _ first: AuditedFlight,
    _ second: AuditedFlight,
    tolerances: AuditTolerances,
    into collector: inout FindingCollector
  ) {
    let firstValues = comparedValues(first)
    let secondValues = comparedValues(second)
    let isExact =
      firstValues == secondValues && first.flight.approaches == second.flight.approaches
      && first.flight.crew == second.flight.crew
    guard
      isCandidate(
        first,
        second,
        firstValues,
        secondValues,
        isExact: isExact,
        tolerances: tolerances
      )
    else { return }

    let names = Set(firstValues.keys).union(secondValues.keys).sorted()
    var differences = [String: JSONValue]()
    for name in names where firstValues[name] != secondValues[name] {
      differences[name] = [firstValues[name].evidenceJSON, secondValues[name].evidenceJSON]
    }
    let isProtected = [first, second].contains { $0.flight.isLocked || $0.flight.isSigned }
    collector.emit(
      isExact ? .duplicateExact : .duplicateCandidate,
      [first.id, second.id],
      message: String(
        localized:
          "These entries may be duplicates. Review ownership, times, approaches and signatures before merging them.",
        bundle: .module
      ),
      evidence: ["different_fields": .object(differences), "locked_or_signed": .bool(isProtected)],
      severity: isExact ? .questionable : .suggestion,
      explanation: isExact
        ? String(
          localized:
            "These entries match on date, aircraft, places, times and every other logged value, so one is almost certainly a copy of the other.",
          bundle: .module
        )
        : String(
          localized:
            "These entries share a date, aircraft and places, and their times or remarks are close enough that they may describe one flight.",
          bundle: .module
        ),
      recommendation: String(
        localized:
          "Compare the two. If one is a copy, delete it in LogTen, keeping the entry that has signatures or the more complete details. If both flights are real, keep them as logged.",
        bundle: .module
      )
    )
  }

  private func comparedValues(_ flight: AuditedFlight) -> [String: FieldValue] {
    flight.values.filter { !Self.ignoredNames.contains($0.key) }
  }

  private func isCandidate(
    _ first: AuditedFlight,
    _ second: AuditedFlight,
    _ firstValues: [String: FieldValue],
    _ secondValues: [String: FieldValue],
    isExact: Bool,
    tolerances: AuditTolerances
  ) -> Bool {
    if let firstOut = first.flight.events.out, let secondOut = second.flight.events.out {
      let delta = abs(PythonTimestamp.minutes(from: firstOut, to: secondOut))
      return delta <= Double(tolerances.duplicateTimeMinutes)
    }
    if isExact { return true }

    let firstRemarks = normalizedRemarks(firstValues)
    let secondRemarks = normalizedRemarks(secondValues)
    if let firstLesson = lesson(in: firstRemarks), let secondLesson = lesson(in: secondRemarks),
      firstLesson != secondLesson
    {
      return false
    }
    if !firstRemarks.isEmpty && !secondRemarks.isEmpty
      && TextSimilarity.ratio(firstRemarks, secondRemarks) < Self.minimumRemarkSimilarity
    {
      return false
    }
    if firstRemarks.isEmpty && secondRemarks.isEmpty {
      guard let firstTotal = first.number("totaltime"), let secondTotal = second.number("totaltime")
      else { return false }
      return abs(firstTotal - secondTotal) <= Double(tolerances.duplicateTimeMinutes)
    }
    return true
  }

  private func normalizedRemarks(_ values: [String: FieldValue]) -> String {
    (values["remarks"]?.text ?? "").lowercased()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  private func lesson(in remarks: String) -> Substring? {
    remarks.firstMatch(of: Self.lessonPattern)?.output.1
  }

  private struct GroupKey: Hashable {
    let date: String
    let registration: String
    let from: String?
    let to: String?
  }
}
