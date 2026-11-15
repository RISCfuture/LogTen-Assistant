public import Foundation
public import LogbookModel

/**
 A portable set of review decisions for one audit run, with the findings selected for
 correction.

 An export names the run it was made against, and ``validated(against:)`` refuses it for any
 other run, so decisions can't silently attach to findings computed from different data.
 */
public struct ReviewExport: Hashable, Codable, Sendable {
  /// The export format's version.
  public static let currentSchemaVersion = 1

  /// The export format's version.
  public var schemaVersion: Int

  /// The run the decisions were made against.
  public var auditID: AuditIdentity

  /// The decisions, one per finding at most.
  public var decisions: [ReviewRecord]

  /// The findings selected for correction, which must be exactly those decided as
  /// ``ReviewDecision/correction``.
  public var selectedFindingIDs: [FindingID]

  /// Creates an export of decisions, selecting every finding decided as a correction.
  public init(audit: ReviewedAudit, decisions: [ReviewRecord]) {
    schemaVersion = Self.currentSchemaVersion
    auditID = audit.identity
    self.decisions = decisions
    selectedFindingIDs = decisions.filter { $0.decision == .correction }.map(\.findingID)
  }

  /**
   Checks the export against the run it claims to describe.

   - Parameter audit: The run to apply the decisions to.
   - Returns: The decisions.
   - Throws: ``ReviewExportError`` if the export is for another run, names an unknown finding,
     decides a finding twice, or selects findings other than its corrections.
   */
  public func validated(against audit: ReviewedAudit) throws(ReviewExportError) -> [ReviewRecord] {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw .unsupportedSchemaVersion(schemaVersion)
    }
    guard auditID == audit.identity else { throw .auditMismatch }
    let known = Set(audit.findings.map(\.id))
    var seen = Set<FindingID>()
    for decision in decisions {
      guard known.contains(decision.findingID) else { throw .unknownFinding(decision.findingID) }
      guard seen.insert(decision.findingID).inserted else {
        throw .duplicateDecision(decision.findingID)
      }
    }
    let corrections = Set(decisions.filter { $0.decision == .correction }.map(\.findingID))
    guard Set(selectedFindingIDs) == corrections,
      selectedFindingIDs.count == Set(selectedFindingIDs).count
    else { throw .selectionMismatch }
    return decisions
  }
}

/// Why a review export can't be used.
public enum ReviewExportError: Error, Equatable, Sendable {
  /// The export uses a format this version doesn't read.
  case unsupportedSchemaVersion(Int)
  /// The export was made against a different audit run.
  case auditMismatch
  /// The export decides a finding the run doesn't have.
  case unknownFinding(FindingID)
  /// The export decides a finding more than once.
  case duplicateDecision(FindingID)
  /// The findings selected for correction aren't exactly those decided as corrections.
  case selectionMismatch
}

extension ReviewExportError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "The review decisions can’t be imported.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case .unsupportedSchemaVersion(let version):
        String(
          localized:
            "The file uses version \(version, format: .number.grouping(.never)) of the decision format, which this version of the app doesn’t read.",
          bundle: .module
        )
      case .auditMismatch:
        String(
          localized: "The decisions were made against a different audit of this logbook.",
          bundle: .module
        )
      case .unknownFinding(let id):
        String(
          localized: "The file decides finding \(id.rawValue), which this audit doesn’t have.",
          bundle: .module
        )
      case .duplicateDecision(let id):
        String(
          localized: "The file decides finding \(id.rawValue) more than once.",
          bundle: .module
        )
      case .selectionMismatch:
        String(
          localized: "The findings selected for correction don’t match the correction decisions.",
          bundle: .module
        )
    }
  }

  public var recoverySuggestion: String? {
    self == .auditMismatch
      ? String(
        localized: "Run the audit the decisions were exported from, or review this audit again.",
        bundle: .module
      )
      : nil
  }
}
