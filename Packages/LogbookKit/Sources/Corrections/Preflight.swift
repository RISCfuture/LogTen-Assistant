import Foundation
public import LogbookModel

/**
 Checks approved corrections against a fresh snapshot just before they are applied.

 An operation is excluded, with every reason that applies, when a record it involves is gone or
 has changed since the audit, when its flight is locked, signed, has no flight key or shares
 its key, when a field isn't importable, when the value the change expects to replace isn't the
 value the flight holds now, or when another operation sets the same field differently.
 Excluded operations go to a ``ManualChecklist`` instead of LogTen's import.
 */
public enum Preflight {
  /**
   Checks a proposal.

   - Parameters:
     - proposal: The approved corrections.
     - logbook: A snapshot taken just now.
   - Returns: The operations ready to apply, and those excluded with their reasons.
   */
  public static func check(_ proposal: CorrectionProposal, against logbook: Logbook)
    -> PreflightResult
  {
    let index = FlightIndex(logbook)
    var issues = proposal.operations.map { operation in
      recordIssues(operation, logbook: logbook, index: index)
        + operation.changes.flatMap { changeIssues($0, index: index) }
    }
    markConflicts(proposal.operations, issues: &issues)

    var result = PreflightResult()
    for (operation, operationIssues) in zip(proposal.operations, issues) {
      if operationIssues.isEmpty {
        result.ready.append(operation)
      } else {
        result.excluded.append(
          ExcludedOperation(operation: operation, issues: unique(operationIssues))
        )
      }
    }
    result.checklist = ManualChecklist(excluded: result.excluded, logbook: logbook)
    return result
  }

  /**
   Checks changes that aren't tied to findings, such as a batch's compensating changes.

   - Returns: The issues of each change, empty for a change that can be applied.
   */
  public static func check(_ changes: [FieldChange], against logbook: Logbook) -> [[PreflightIssue]]
  {
    let index = FlightIndex(logbook)
    return changes.map { unique(changeIssues($0, index: index)) }
  }

  private static func recordIssues(
    _ operation: CorrectionOperation,
    logbook: Logbook,
    index: FlightIndex
  ) -> [PreflightIssue] {
    var issues = [PreflightIssue]()
    for (id, expected) in operation.recordFingerprints.sorted(by: { $0.key < $1.key }) {
      guard let current = logbook.fingerprints[id] else {
        issues.append(.recordMissing(id))
        continue
      }
      if let flight = index.flights[id] { issues += protectionIssues(flight) }
      if current != expected { issues.append(.recordChanged(id)) }
    }
    if operation.changes.isEmpty { issues.append(.noChanges) }
    return issues
  }

  private static func changeIssues(_ change: FieldChange, index: FlightIndex) -> [PreflightIssue] {
    guard change.field.entity == .flight else { return [.fieldNotImportable(change.field)] }
    guard let flight = index.flights[change.recordID] else {
      return [.recordMissing(change.recordID)]
    }
    var issues = protectionIssues(flight)
    if !ImportField.isImportable(change.field) { issues.append(.fieldNotImportable(change.field)) }
    if let key = flight.flightKey, !key.isEmpty {
      if change.flightKey != key { issues.append(.flightKeyChanged(flight.id)) }
      if index.flightKeyCounts[key, default: 0] > 1 {
        issues.append(.flightKeyNotUnique(flight.id))
      }
    } else {
      issues.append(.missingFlightKey(flight.id))
    }
    let current = flight[field: change.field]
    if !current.matches(flight.normalized(change.old, for: change.field)) {
      issues.append(.oldValueMismatch(flight.id, change.field, current: current))
    }
    return issues
  }

  private static func protectionIssues(_ flight: Flight) -> [PreflightIssue] {
    (flight.isLocked ? [.locked(flight.id)] : []) + (flight.isSigned ? [.signed(flight.id)] : [])
  }

  private static func markConflicts(
    _ operations: [CorrectionOperation],
    issues: inout [[PreflightIssue]]
  ) {
    struct Target: Hashable {
      let recordID: RecordID
      let field: LogTenFieldKey
    }
    var values = [Target: Set<FieldValue>]()
    var owners = [Target: [Int]]()
    for (position, operation) in operations.enumerated() where issues[position].isEmpty {
      for change in operation.changes {
        let target = Target(recordID: change.recordID, field: change.field)
        values[target, default: []].insert(change.new)
        owners[target, default: []].append(position)
      }
    }
    for (target, newValues) in values where newValues.count > 1 {
      for position in owners[target] ?? [] {
        issues[position].append(.conflictingChange(target.recordID, target.field))
      }
    }
  }

  private static func unique(_ issues: [PreflightIssue]) -> [PreflightIssue] {
    var seen = Set<PreflightIssue>()
    return issues.filter { seen.insert($0).inserted }
  }
}

/// The outcome of a preflight check.
public struct PreflightResult: Hashable, Codable, Sendable {
  /// The operations that can be applied through LogTen's import.
  public var ready = [CorrectionOperation]()

  /// The operations that can't, with their reasons.
  public var excluded = [ExcludedOperation]()

  /// The excluded changes, as instructions for making them by hand.
  public var checklist = ManualChecklist(items: [])

  /// The changes of the ready operations, each flight's field once.
  public var readyChanges: [FieldChange] {
    var seen = Set<[String]>()
    return ready.flatMap(\.changes).filter {
      seen.insert([$0.recordID.rawValue, $0.field.rawValue]).inserted
    }
  }
}

/// An operation preflight excluded.
public struct ExcludedOperation: Hashable, Codable, Sendable {
  /// The operation.
  public var operation: CorrectionOperation

  /// Every reason it can't be applied.
  public var issues: [PreflightIssue]

  /// Creates an excluded operation.
  public init(operation: CorrectionOperation, issues: [PreflightIssue]) {
    self.operation = operation
    self.issues = issues
  }
}

/// Why a change can't be applied through LogTen's import.
public enum PreflightIssue: Hashable, Codable, Sendable {
  /// The record no longer exists.
  case recordMissing(RecordID)
  /// The record changed after the finding was approved.
  case recordChanged(RecordID)
  /// The flight is locked.
  case locked(RecordID)
  /// The flight is signed; unlocking it to change it removes the signature.
  case signed(RecordID)
  /// The flight has no flight key, so the import can't address it.
  case missingFlightKey(RecordID)
  /// The flight's key isn't the one the change was proposed with.
  case flightKeyChanged(RecordID)
  /// Another flight has the same key, so the import can't tell them apart.
  case flightKeyNotUnique(RecordID)
  /// The field can't be changed through the import.
  case fieldNotImportable(LogTenFieldKey)
  /// The field no longer holds the value the change replaces.
  case oldValueMismatch(RecordID, LogTenFieldKey, current: FieldValue)
  /// Another approved finding sets the same field to a different value.
  case conflictingChange(RecordID, LogTenFieldKey)
  /// The finding proposes no change.
  case noChanges

  /// Whether the change can still be made by editing the entry in LogTen.
  public var allowsManualEdit: Bool {
    switch self {
      case .missingFlightKey, .flightKeyNotUnique, .fieldNotImportable, .locked, .signed: true
      default: false
    }
  }

  /// A description of the issue for the manual checklist.
  public var explanation: String {
    switch self {
      case .recordMissing:
        String(localized: "The entry no longer exists.", bundle: .module)
      case .recordChanged:
        String(localized: "The entry changed after the finding was approved.", bundle: .module)
      case .locked:
        String(localized: "The entry is locked.", bundle: .module)
      case .signed:
        String(
          localized: "The entry is signed; changing it removes the signature.",
          bundle: .module
        )
      case .missingFlightKey:
        String(localized: "The entry has no flight key for LogTen’s import.", bundle: .module)
      case .flightKeyChanged:
        String(localized: "The entry’s flight key changed.", bundle: .module)
      case .flightKeyNotUnique:
        String(localized: "Another entry has the same flight key.", bundle: .module)
      case .fieldNotImportable(let field):
        String(
          localized: "\(field.rawValue) can’t be changed through LogTen’s import.",
          bundle: .module
        )
      case .oldValueMismatch:
        String(
          localized: "The field no longer holds the value the change replaces.",
          bundle: .module
        )
      case .conflictingChange:
        String(localized: "Another approved finding sets this field differently.", bundle: .module)
      case .noChanges:
        String(localized: "The finding proposes no change.", bundle: .module)
    }
  }
}

/// The flights of a snapshot by identifier, with how many flights use each key.
struct FlightIndex {
  let flights: [RecordID: Flight]
  let flightKeyCounts: [String: Int]

  init(_ logbook: Logbook) {
    flights = Dictionary(logbook.flights.map { ($0.id, $0) }) { first, _ in first }
    var counts = [String: Int]()
    for key in logbook.flights.compactMap(\.flightKey) where !key.isEmpty {
      counts[key, default: 0] += 1
    }
    flightKeyCounts = counts
  }
}

extension Flight {
  /// A value as this flight would store it in a field: typed fields read ``FieldValue/null``
  /// back as zero or false.
  func normalized(_ value: FieldValue, for field: LogTenFieldKey) -> FieldValue {
    var copy = self
    copy[field: field] = value
    return copy[field: field]
  }
}

extension FieldValue {
  private static let dateTolerance: TimeInterval = 0.001

  /// Whether two values are the same, allowing for floating-point rounding of dates and the
  /// single precision LogTen stores numbers such as Hobbs readings in.
  func matches(_ other: Self) -> Bool {
    switch (self, other) {
      case let (.date(first), .date(second)):
        abs(first.timeIntervalSince(second)) < Self.dateTolerance
      case let (.number(first), .number(second)):
        Float(first) == Float(second)
      default: self == other
    }
  }
}
