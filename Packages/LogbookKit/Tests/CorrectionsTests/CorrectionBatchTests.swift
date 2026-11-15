import Foundation
import Corrections
import LogbookModel
import Testing

@Suite
struct `Correction batches` {
  private func change(_ flightKey: String?, _ field: LogTenFieldKey = .flightNight) -> FieldChange {
    FieldChange(
      flightKey: flightKey,
      recordID: RecordID(rawValue: flightKey ?? "unkeyed"),
      field: field,
      old: .integer(0),
      new: .integer(30)
    )
  }

  @Test
  func `starts with a one-flight pilot batch and keeps each flight's changes together`() {
    let changes = [
      change("A"), change("B"), change("A", .flightTotalTime), change("C"), change("D"),
      change("E"), change(nil)
    ]
    let batches = CorrectionBatch.plan(changes, maximumFlights: 2)

    #expect(batches.map(\.flightKeys) == [["A"], ["B", "C"], ["D", "E"]])
    #expect(batches[0].changes.map(\.field) == [.flightNight, .flightTotalTime])
  }

  @Test
  func `identifies batches by their content`() {
    let first = CorrectionBatch(changes: [change("A")])
    #expect(first.id == CorrectionBatch(changes: [change("A")]).id)
    #expect(first.id != CorrectionBatch(changes: [change("B")]).id)
  }

  @Test
  func `fills later batches up to the URL length limit`() throws {
    let changes = ["A", "B", "C", "D", "E"].map { change($0) }
    let metadata = ImportPackageMetadata(version: "1.0")
    let twoFlights = try ImportPackage(
      batch: CorrectionBatch(changes: [change("B"), change("C")]),
      metadata: metadata
    )
    let limit = twoFlights.url.absoluteString.count

    let batches = try CorrectionBatch.plan(changes, maximumURLLength: limit, metadata: metadata)
    #expect(batches.map(\.flightKeys) == [["A"], ["B", "C"], ["D", "E"]])
  }

  @Test
  func `compensates by restoring each field's old value`() {
    let batch = CorrectionBatch(changes: [change("A")])
    #expect(batch.compensating.changes.map(\.new) == [.integer(0)])
    #expect(batch.compensating.changes.map(\.old) == [.integer(30)])
    #expect(batch.compensating.compensating == batch)
  }
}
