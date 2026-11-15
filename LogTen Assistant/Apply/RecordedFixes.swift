import Corrections
import Foundation
import LogbookModel

extension ApplyJournal {
  /// When each change was last recorded, from the recorded batches that don't revert another.
  private var changeRecordingDates: [FieldChange: Date] {
    entries.filter { $0.isRecorded && $0.revertedEntryID == nil }
      .reduce(into: [:]) { dates, entry in
        for change in entry.batch.changes {
          dates[change] = max(dates[change] ?? .distantPast, entry.receipt.deliveredAt)
        }
      }
  }

  /**
   When approved fixes were recorded to disk instead of sent to LogTen.

   Recording leaves the logbook as it was, so a recorded fix stays approved and the next apply
   offers it again.

   - Parameter corrections: The approved fixes.
   - Returns: For each fix whose every change a recorded batch holds, when the latest of those
     batches was recorded.
   */
  func recordedDates(of corrections: [ApprovedCorrection]) -> [FindingID: Date] {
    let recordedAt = changeRecordingDates
    return corrections.reduce(into: [:]) { dates, correction in
      let changes = correction.option.changes
      let changeDates = changes.compactMap { recordedAt[$0] }
      guard changeDates.count == changes.count, let latest = changeDates.max() else { return }
      dates[correction.finding.id] = latest
    }
  }
}

extension ApplyJournalEntry {
  /// Whether the batch was recorded to disk rather than sent to LogTen.
  var isRecorded: Bool { receipt.recordedFile != nil }
}

extension LogbookSession {
  /// When each approved fix was recorded rather than sent to LogTen, by finding.
  var recordedFixDates: [FindingID: Date] {
    journal?.recordedDates(of: approvedCorrections) ?? [:]
  }
}

/// How a recorded fix is described: “Recorded Nov 9 — not sent to LogTen”.
enum RecordedFixText {
  /// The note for one fix recorded on a date.
  static func note(recordedAt date: Date) -> String {
    String(localized: "Recorded \(date, format: .dateTime.month().day()) — not sent to LogTen")
  }
}
