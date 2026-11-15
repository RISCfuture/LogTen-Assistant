import Foundation
import LogbookModel

/// Evaluates the logbook's user-defined rules on every flight.
struct CustomRuleChecks {
  let rules: [CustomRule]
  let logbook: Logbook

  func check(_ flights: [AuditedFlight], into collector: inout FindingCollector) {
    for rule in rules {
      let field = AuditedFlight.name(of: rule.field)
      let other = rule.other.map(AuditedFlight.name)
      for flight in flights where fails(rule, flight[field], other.flatMap { flight[$0] }) {
        var evidence: [String: JSONValue] = [field: flight[field].evidenceJSON]
        if let other { evidence[other] = flight[other].evidenceJSON }
        collector.emit(
          rule.findingRule,
          [flight.id],
          message: message(for: rule),
          evidence: .object(evidence),
          severity: rule.severity
        )
      }
    }
  }

  private func fails(_ rule: CustomRule, _ value: FieldValue?, _ other: FieldValue?) -> Bool {
    switch rule.kind {
      case .subset:
        guard let value = value?.numeric, let other = other?.numeric else { return false }
        return value > other
      case .nonnegative:
        return (value?.numeric ?? 0) < 0
      case .requires:
        return value?.isSet == true && other?.isSet != true
    }
  }

  private func message(for rule: CustomRule) -> String {
    let field = logbook.title(of: rule.field)
    let other = rule.other.map(logbook.title) ?? ""
    return switch rule.kind {
      case .subset: String(localized: "\(field) exceeds \(other).", bundle: .module)
      case .nonnegative: String(localized: "\(field) is negative.", bundle: .module)
      case .requires: String(localized: "\(field) is set but \(other) isn’t.", bundle: .module)
    }
  }
}

extension FieldValue {
  /// The value as a number, treating Booleans as 0 or 1 as SQLite stores them.
  fileprivate var numeric: Double? {
    switch self {
      case .integer(let value): Double(value)
      case .number(let value): value
      case .boolean(let value): value ? 1 : 0
      default: nil
    }
  }
}
