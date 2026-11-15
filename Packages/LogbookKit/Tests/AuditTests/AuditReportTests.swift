import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Audit reports` {
  @Test
  func `orders findings by rule then identifier and finds those involving a record`() {
    let first = RecordID(rawValue: "F1")
    let second = RecordID(rawValue: "F2")
    let zeroTimes = [first, "F3", "F4"].map {
      Finding(rule: "zero_time", recordIDs: [$0], message: "")
    }
    let duplicate = Finding(rule: "duplicate_flight", recordIDs: [first, second], message: "")
    let report = AuditReport(
      identity: LogbookIdentity(storeUUID: UUID()),
      generatedAt: .now,
      findings: zeroTimes.sorted { $0.id > $1.id } + [duplicate]
    )

    #expect(report.findings.first == duplicate)
    #expect(report.findings.dropFirst().map(\.id) == zeroTimes.map(\.id).sorted())
    #expect(report.findings(involving: second) == [duplicate])
  }
}
