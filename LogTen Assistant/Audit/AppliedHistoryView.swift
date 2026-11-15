import Corrections
import LogbookModel
import SwiftUI

/// Audit & Fix ▸ Applied History: every batch delivered, newest first. The selected batch's
/// details are in the inspector.
struct AppliedHistoryView: View {
  let session: LogbookSession

  private var allEntries: [ApplyJournalEntry] {
    (session.journal?.entries ?? []).sorted { $0.receipt.deliveredAt > $1.receipt.deliveredAt }
  }

  private var entries: [ApplyJournalEntry] {
    allEntries.filter { session.matchesSearch($0) }
  }

  var body: some View {
    Group {
      if allEntries.isEmpty {
        ContentUnavailableView(
          "Nothing Applied",
          systemImage: "clock.arrow.circlepath",
          description: Text("Batches you apply appear here, with their verification.")
        )
      } else if entries.isEmpty {
        ContentUnavailableView.search(text: session.searchText)
      } else {
        HistoryTable(session: session, entries: entries)
      }
    }
    .modifier(RevertConfirmation(session: session, entries: allEntries))
  }
}

/// The table of delivered batches.
private struct HistoryTable: View {
  let session: LogbookSession
  let entries: [ApplyJournalEntry]

  var body: some View {
    Table(entries, selection: selection) {
      TableColumn("Applied") { entry in
        Text(entry.receipt.deliveredAt.formatted(date: .abbreviated, time: .shortened))
      }
      TableColumn("Action") { entry in
        Text(entry.actionTitle)
      }
      TableColumn("Flights") { entry in
        Text(entry.batch.recordIDs.count, format: .number).monospacedDigit()
      }
      .width(ideal: 60)
      .alignment(.trailing)
      TableColumn("Changes") { entry in
        Text(entry.batch.changes.count, format: .number).monospacedDigit()
      }
      .width(ideal: 60)
      .alignment(.trailing)
      TableColumn("Status") { entry in
        Label(entry.displayStatus, systemImage: entry.statusSymbol)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(.primary)
      }
    }
    .contextMenu(forSelectionType: ApplyJournalEntry.ID.self) { ids in
      Button("Revert Batch…") { session.revertingEntryID = ids.first }
        .disabled(!canRevert(ids))
    }
    .accessibilityIdentifier("appliedHistory")
  }

  private var selection: Binding<ApplyJournalEntry.ID?> {
    Binding {
      session.selectedJournalEntryID
    } set: {
      session.selectedJournalEntryID = $0
    }
  }

  private func canRevert(_ ids: Set<ApplyJournalEntry.ID>) -> Bool {
    guard ids.count == 1, let entry = entries.first(where: { ids.contains($0.id) }) else {
      return false
    }
    return session.canRevert(entry)
  }
}

extension ApplyJournalEntry {
  /// What the batch did: applied fixes, or reverted an earlier batch.
  var actionTitle: String {
    revertedEntryID == nil ? String(localized: "Applied Fixes") : String(localized: "Revert")
  }

  /// The batch's status, or “Recorded” when it was saved to disk instead of sent.
  var displayStatus: String {
    receipt.recordedFile == nil ? status.title : String(localized: "Recorded")
  }
}

extension ApplyJournalEntry {
  /// A monochrome symbol for the batch's status; recorded batches get a document.
  var statusSymbol: String {
    guard receipt.recordedFile == nil else { return "doc.text" }
    return switch status {
      case .delivered: "clock"
      case .verified: "checkmark.circle"
      case .failed: "xmark.circle"
    }
  }
}

/// Presents the revert confirmation for `session.revertingEntryID`: a sheet that asks for the
/// LogTen backup acknowledgement when batches go to LogTen, a dialog when they only get recorded.
private struct RevertConfirmation: ViewModifier {
  let session: LogbookSession
  let entries: [ApplyJournalEntry]

  private var entry: ApplyJournalEntry? {
    entries.first { $0.id == session.revertingEntryID }
  }

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: isPresented(sending: true)) {
        if let entry {
          RevertSheet(entry: entry, cancel: dismiss) { revert(entry) }
        }
      }
      .confirmationDialog(
        "Revert this batch?",
        isPresented: isPresented(sending: false),
        presenting: entry
      ) { entry in
        Button("Revert Batch", role: .destructive) { revert(entry) }
      } message: { entry in
        Text(
          "This records the ^[\(entry.batch.changes.count) original value](inflect: true), after checking that the flights haven’t changed since."
        )
      }
  }

  private func isPresented(sending: Bool) -> Binding<Bool> {
    Binding {
      entry != nil && session.sendsToLogTen == sending
    } set: {
      if !$0 { dismiss() }
    }
  }

  private func dismiss() {
    session.revertingEntryID = nil
  }

  private func revert(_ entry: ApplyJournalEntry) {
    dismiss()
    Task { await session.revert(entry.id) }
  }
}

/// The confirmation for reverting a batch sent to LogTen, which changes the user’s real logbook.
struct RevertSheet: View {
  let entry: ApplyJournalEntry
  let cancel: () -> Void
  let revert: () -> Void

  @State private var confirmsLogTenBackup = false

  var body: some View {
    VStack(alignment: .leading) {
      Text("Revert This Batch").font(.headline)
      Text(
        "Make a backup in LogTen first: choose View ▸ Backups and click +. This sends LogTen the ^[\(entry.batch.changes.count) original value](inflect: true), after checking that the flights haven’t changed since."
      )
      LogTenBackupToggle(isOn: $confirmsLogTenBackup, identifier: "revert.confirmsLogTenBackup")
      HStack {
        Spacer()
        Button("Cancel", action: cancel)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("revert.cancel")
        Button("Revert Batch", role: .destructive, action: revert)
          .keyboardShortcut(.defaultAction)
          .disabled(!confirmsLogTenBackup)
          .accessibilityIdentifier("revert.confirm")
      }
    }
    .padding()
    .frame(width: 420)
  }
}

#Preview(
  "With Entries",
  traits: .sampleSession(PreviewHelper.selectAppliedBatch)
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Nothing Applied",
  traits: .sampleSession { $0.sidebarSelection = .audit(.appliedHistory) }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview("Revert Sheet") {
  RevertSheet(entry: PreviewHelper.journalEntry(of: PreviewHelper.flight), cancel: {}, revert: {})
}
