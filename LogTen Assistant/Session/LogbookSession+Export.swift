import AuditWorkflow
import Foundation
import Review
import UniformTypeIdentifiers

/// The file formats findings can be exported in.
enum FindingExportFormat: CaseIterable {
  case csv
  case json

  var type: UTType {
    switch self {
      case .csv: .commaSeparatedText
      case .json: .json
    }
  }

  var title: String {
    switch self {
      case .csv: String(localized: "CSV")
      case .json: String(localized: "JSON")
    }
  }
}

extension LogbookSession {
  /// Whether there are findings to export.
  var canExport: Bool { auditRun != nil }

  /// Asks where to save the findings, with their decisions, and saves them.
  func exportFindings(as format: FindingExportFormat) {
    guard let auditRun else { return }
    let exporter = FindingExporter(findings: auditRun.findings, book: reviewBook, logbook: logbook)
    save(
      named: String(localized: "\(reference.title) Findings"),
      type: format.type,
      title: String(localized: "Export Findings")
    ) {
      switch format {
        case .csv: Data(exporter.csv().utf8)
        case .json: try exporter.json()
      }
    }
  }

  /// Asks where to save the review decisions, as JSON tied to this run, and saves them.
  func exportReviewDecisions() {
    guard let reviewedAudit else { return }
    let export = ReviewExport(audit: reviewedAudit, decisions: reviewBook.orderedRecords)
    save(
      named: String(localized: "\(reference.title) Review Decisions"),
      type: .json,
      title: String(localized: "Export Review Decisions")
    ) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      return try encoder.encode(export)
    }
  }

  private func save(
    named name: String,
    type: UTType,
    title: String,
    contents: () throws -> Data
  ) {
    guard let url = FilePanels.saveLocation(named: name, type: type, title: title) else { return }
    do {
      try contents().write(to: url, options: .atomic)
    } catch {
      actionError = error
    }
  }
}
