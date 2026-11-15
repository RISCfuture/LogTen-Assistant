import Audit
import AuditWorkflow
import Foundation
import LogbookModel
import Regulations

/// An entry in a logbook window's sidebar.
nonisolated enum SidebarItem: Hashable, Sendable {
  /// A page of the Audit & Fix workflow.
  case audit(AuditPage)

  /// The logbook-consistency findings of one category of checks.
  case checks(ConsistencyCategory)

  /// The violations of one rule, or of every rule when `nil`.
  case violations(RegulationRule?)

  /// The pages the View menu selects with ⌘1 through ⌘8, in order.
  static let pages = AuditPage.allCases.map(Self.audit) + [.violations(nil)]

  /// The findings the item lists for review, if it lists any.
  var findingList: FindingList? {
    switch self {
      case .audit(let page): page.queue.map { FindingList(queue: $0) }
      case .checks(let category): FindingList(queue: .logbookConsistency, category: category)
      case .violations: nil
    }
  }
}

/// The findings a review page lists: a queue's, or those of one category of its checks.
nonisolated struct FindingList: Hashable, Sendable {
  /// The queue the findings are in.
  let queue: ReviewQueue

  /// The category of consistency checks the findings come from, or `nil` for the whole queue.
  var category: ConsistencyCategory?

  /// A name for the list in accessibility identifiers, such as `logbook_consistency` or
  /// `checks.times`.
  var identifier: String { category.map { "checks.\($0.rawValue)" } ?? queue.rawValue }

  /// Whether the list holds a finding of the queue.
  func contains(_ finding: Finding) -> Bool {
    guard let category else { return true }
    return ConsistencyRule(id: finding.rule)?.category == category
  }
}

/// The pages of the Audit & Fix workflow.
nonisolated enum AuditPage: String, CaseIterable, Sendable {
  case dataSources = "data_sources"
  case logbookConsistency = "logbook_consistency"
  case aircraftComparisons = "aircraft_comparisons"
  case unmatchedActivity = "unmatched_activity"
  case groupsAndCurrency = "groups_and_currency"
  case approved
  case appliedHistory = "applied_history"
}

nonisolated extension SidebarItem: RawRepresentable {
  private static let allViolationsRawValue = "violations"
  private static let auditPrefix = "audit/"
  private static let rulePrefix = "violations/"
  private static let checksPrefix = "checks/"

  var rawValue: String {
    switch self {
      case .audit(let page): Self.auditPrefix + page.rawValue
      case .checks(let category): Self.checksPrefix + category.rawValue
      case .violations(nil): Self.allViolationsRawValue
      case .violations(let rule?): Self.rulePrefix + rule.rawValue
    }
  }

  init?(rawValue: String) {
    if rawValue == Self.allViolationsRawValue {
      self = .violations(nil)
    } else if rawValue.hasPrefix(Self.auditPrefix),
      let page = AuditPage(rawValue: String(rawValue.dropFirst(Self.auditPrefix.count)))
    {
      self = .audit(page)
    } else if rawValue.hasPrefix(Self.checksPrefix),
      let category = ConsistencyCategory(
        rawValue: String(rawValue.dropFirst(Self.checksPrefix.count))
      )
    {
      self = .checks(category)
    } else if rawValue.hasPrefix(Self.rulePrefix),
      let rule = RegulationRule(rawValue: String(rawValue.dropFirst(Self.rulePrefix.count)))
    {
      self = .violations(rule)
    } else {
      return nil
    }
  }
}
