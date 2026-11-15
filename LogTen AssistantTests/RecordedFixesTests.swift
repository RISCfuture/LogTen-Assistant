import Corrections
import Foundation
import LogbookModel
import Testing

@testable import LogTen_Assistant

@MainActor
struct RecordedFixesTests {
  private static let day = Date(timeIntervalSince1970: 1_793_889_120)
  private static let flight = RecordID(rawValue: "A")
  private static let metadata = ImportPackageMetadata(version: "1.0")

  private static func change(_ field: LogTenFieldKey, to value: Int) -> FieldChange {
    FieldChange(
      flightKey: "KEY-A",
      recordID: Self.flight,
      field: field,
      old: .integer(60),
      new: .integer(value)
    )
  }

  private static func fix(_ changes: FieldChange...) -> ApprovedCorrection {
    let option = CorrectionOption(title: "Fix", changes: changes)
    let finding = Finding(
      rule: "seat_time",
      recordIDs: [Self.flight],
      message: "Logged as both PIC and SIC.",
      evidence: ["changes": .string(option.id.rawValue)],
      corrections: [option]
    )
    return ApprovedCorrection(finding: finding, option: option)
  }

  private static func journal(_ deliveries: Delivery...) throws -> ApplyJournal {
    var journal = ApplyJournal(storeUUID: UUID())
    var entryIDs = [UUID]()
    for delivery in deliveries {
      let batch = CorrectionBatch(changes: delivery.changes)
      let file = delivery.isRecorded ? URL(filePath: "/tmp/\(batch.id).json") : nil
      entryIDs.append(
        journal.recordDelivery(
          of: batch,
          package: try ImportPackage(batch: batch, metadata: metadata),
          receipt: WriteReceipt(
            batchID: batch.id,
            deliveredAt: day.addingTimeInterval(delivery.hoursLater * 3_600),
            recordedFile: file
          ),
          reverting: delivery.reverts.map { entryIDs[$0] }
        )
      )
    }
    return journal
  }

  @Test
  func aFixCountsOnlyWhenARecordedBatchHoldsEveryOneOfItsChanges() throws {
    let pic = Self.change(.flightPIC, to: 0)
    let sic = Self.change(.flightSIC, to: 0)
    let both = Self.fix(pic, sic)

    let whole = try Self.journal(Delivery(changes: [pic, sic]))
    #expect(whole.recordedDates(of: [both])[both.finding.id] == Self.day)

    let partial = try Self.journal(Delivery(changes: [pic]))
    #expect(partial.recordedDates(of: [both]).isEmpty)

    let acrossBatches = try Self.journal(
      Delivery(changes: [pic]),
      Delivery(changes: [sic], hoursLater: 2)
    )
    #expect(
      acrossBatches.recordedDates(of: [both])[both.finding.id]
        == Self.day.addingTimeInterval(2 * 3_600)
    )
  }

  @Test
  func theLatestRecordingWins() throws {
    let pic = Self.change(.flightPIC, to: 0)
    let journal = try Self.journal(
      Delivery(changes: [pic], hoursLater: 5),
      Delivery(changes: [pic], hoursLater: 1)
    )
    let fix = Self.fix(pic)
    #expect(
      journal.recordedDates(of: [fix])[fix.finding.id] == Self.day.addingTimeInterval(5 * 3_600)
    )
  }

  @Test
  func batchesSentToLogTenAndBatchesRevertingAnotherDontCount() throws {
    let pic = Self.change(.flightPIC, to: 0)
    let sent = try Self.journal(Delivery(changes: [pic], isRecorded: false))
    #expect(sent.recordedDates(of: [Self.fix(pic)]).isEmpty)

    let compensating = CorrectionBatch(changes: [pic]).compensating.changes
    let reverted = try Self.journal(
      Delivery(changes: [pic]),
      Delivery(changes: compensating, reverts: 0)
    )
    let restoring = Self.fix(compensating[0])
    #expect(reverted.recordedDates(of: [restoring]).isEmpty)
  }

  private struct Delivery {
    let changes: [FieldChange]
    var hoursLater = 0.0
    var isRecorded = true
    var reverts: Int?
  }
}
