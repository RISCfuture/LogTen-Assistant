public import Foundation
public import LogbookModel
import Review

/**
 Writes an audit's findings, with the user's decisions, as CSV or JSON for use outside the app.

 Values are written in machine-readable forms: dates as ISO 8601, and changed values as
 canonical JSON. Each finding's correction options are listed with their changes, alongside the
 one the reviewer chose. The CSV follows RFC 4180, quoting any field that holds a comma, quote or line
 break.
 */
public struct FindingExporter: Sendable {
  private static let header = [
    "id", "queue", "rule", "severity", "flight_date", "registration", "flight_key", "record_ids",
    "message", "explanation", "recommendation", "corrections", "chosen_correction", "decision",
    "reason", "note", "citation"
  ]
  private static let lineBreak = "\r\n"

  private let findings: [Finding]
  private let book: ReviewBook
  private let flights: [RecordID: Flight]

  private var rows: [Row] {
    findings.map { finding in
      let flight = finding.recordIDs.lazy.compactMap { flights[$0] }.first
      let record = book.records[finding.id]
      return Row(
        id: finding.id.rawValue,
        queue: ReviewQueue(rule: finding.rule).rawValue,
        rule: finding.rule.rawValue,
        severity: finding.severity.rawValue,
        flightDate: flight.map { $0.date.formatted(.iso8601.year().month().day()) },
        registration: flight?.aircraft?.registration,
        flightKey: flight?.flightKey,
        recordIDs: finding.recordIDs.map(\.rawValue),
        message: finding.message,
        explanation: finding.explanation,
        recommendation: finding.recommendation,
        corrections: finding.corrections.map(Correction.init),
        chosenCorrection: record?.correctionOptionID?.rawValue,
        decision: (record?.decision ?? .unreviewed).rawValue,
        reason: record?.reason?.rawValue,
        note: record?.note ?? "",
        citation: finding.citation
      )
    }
  }

  /**
   Creates an exporter.

   - Parameters:
     - findings: The findings, in the order to write them.
     - book: The user's decisions.
     - logbook: The snapshot the findings came from, for each finding's flight details.
   */
  public init(findings: [Finding], book: ReviewBook, logbook: Logbook?) {
    self.findings = findings
    self.book = book
    flights = Dictionary((logbook?.flights ?? []).map { ($0.id, $0) }) { first, _ in first }
  }

  private static func quoted(_ field: String) -> String {
    guard field.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) else { return field }
    return "\"" + field.replacing("\"", with: "\"\"") + "\""
  }

  /// The findings as CSV text, one row per finding after a header row.
  public func csv() -> String {
    ([Self.header] + rows.map(\.columns))
      .map { $0.map(Self.quoted).joined(separator: ",") }
      .joined(separator: Self.lineBreak) + Self.lineBreak
  }

  /// The findings as a pretty-printed JSON array of objects with the CSV's columns.
  public func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(rows)
  }

  private struct Row: Encodable {
    let id: String
    let queue: String
    let rule: String
    let severity: String
    let flightDate: String?
    let registration: String?
    let flightKey: String?
    let recordIDs: [String]
    let message: String
    let explanation: String?
    let recommendation: String?
    let corrections: [Correction]
    let chosenCorrection: String?
    let decision: String
    let reason: String?
    let note: String
    let citation: String?

    var columns: [String] {
      [
        id, queue, rule, severity, flightDate ?? "", registration ?? "", flightKey ?? "",
        recordIDs.joined(separator: " "), message, explanation ?? "", recommendation ?? "",
        corrections.map(\.summary).joined(separator: " | "), chosenCorrection ?? "", decision,
        reason ?? "", note, citation ?? ""
      ]
    }

    enum CodingKeys: String, CodingKey {
      case id, queue, rule, severity, registration, message, explanation, recommendation
      case corrections, decision, reason, note, citation
      case chosenCorrection = "chosen_correction"
      case flightDate = "flight_date"
      case flightKey = "flight_key"
      case recordIDs = "record_ids"
    }
  }

  private struct Correction: Encodable {
    let id: String
    let title: String
    let detail: String?
    let changes: [Change]

    var summary: String { "\(title): " + changes.map(\.summary).joined(separator: "; ") }

    init(_ option: CorrectionOption) {
      id = option.id.rawValue
      title = option.title
      detail = option.detail
      changes = option.changes.map(Change.init)
    }
  }

  private struct Change: Encodable {
    let field: String
    let old: String
    let new: String

    var summary: String { "\(field): \(old) -> \(new)" }

    init(_ change: FieldChange) {
      field = change.field.rawValue
      old = CanonicalJSON.string(for: change.old.jsonValue)
      new = CanonicalJSON.string(for: change.new.jsonValue)
    }
  }
}
