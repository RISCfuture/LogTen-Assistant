import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Audit reports` {
  @Test
  func `orders findings by rule and finds those involving a record`() {
    let first = RecordID(rawValue: "F1")
    let second = RecordID(rawValue: "F2")
    let report = AuditReport(
      identity: LogbookIdentity(storeUUID: UUID()),
      generatedAt: .now,
      findings: [
        Finding(rule: "zero_time", recordIDs: [first], message: ""),
        Finding(rule: "duplicate_flight", recordIDs: [first, second], message: "")
      ]
    )
    #expect(report.findings.map(\.rule) == ["duplicate_flight", "zero_time"])
    #expect(report.findings(involving: second).map(\.rule) == ["duplicate_flight"])
  }
}
