import AppKit
import LogbookStore
import SwiftUI

/// The window shown when no logbook is open: open LogTen's logbook, another folder, or a
/// recent logbook.
struct OpenLogbookView: View {
  @State private var selectedRecent: LogbookReference.ID?

  var body: some View {
    HStack(spacing: 0) {
      OpenActionsPane()
        .frame(width: 300)
      Divider()
      RecentLogbooksList(selection: $selectedRecent)
        .frame(maxWidth: .infinity)
    }
    .frame(width: 640, height: 400)
  }
}

/// The app's name and the buttons that start opening a logbook.
private struct OpenActionsPane: View {
  @Environment(\.openLogbook)
  private var openLogbook

  var body: some View {
    VStack(spacing: 20) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
      Text("LogTen Assistant").font(.title)
      VStack {
        Button("Open Default LogTen Logbook…") {
          openLogbook?(.chooseFolder(startingAt: LogbookLocation.defaultGroupContainerURL))
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("openDefaultLogbookButton")
        Button("Open Other Folder…") {
          openLogbook?(.chooseFolder(startingAt: nil))
        }
        .accessibilityIdentifier("openOtherFolderButton")
      }
      .controlSize(.large)
      Text("LogTen Assistant reads a copy of your logbook and never changes it on its own.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxHeight: .infinity)
  }
}

/// The logbooks opened recently.
private struct RecentLogbooksList: View {
  @Binding var selection: LogbookReference.ID?

  @Environment(LogbookLibrary.self)
  private var library
  @Environment(\.openLogbook)
  private var openLogbook

  var body: some View {
    if library.recents.isEmpty {
      ContentUnavailableView(
        "No Recent Logbooks",
        systemImage: "book.closed",
        description: Text("Logbooks you open appear here.")
      )
    } else {
      List(library.recents, selection: $selection) { reference in
        RecentLogbookRow(reference: reference)
      }
      .contextMenu(forSelectionType: LogbookReference.ID.self) { ids in
        Button("Open") { open(ids) }
        Button("Remove from Recents") {
          for reference in library.recents where ids.contains(reference.id) {
            library.remove(reference)
          }
        }
      } primaryAction: { ids in
        open(ids)
      }
      .accessibilityIdentifier("recentLogbooksList")
    }
  }

  private func open(_ ids: Set<LogbookReference.ID>) {
    for reference in library.recents where ids.contains(reference.id) {
      openLogbook?(.reference(reference))
    }
  }
}

/// A recent logbook's name, folder and when it was last opened.
private struct RecentLogbookRow: View {
  let reference: LogbookReference

  var body: some View {
    VStack(alignment: .leading) {
      Text(reference.title)
      if let path = reference.path {
        PathLine(path: path, isDefaultLogbook: reference.isDefaultLogbook)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
          .font(.caption)
      }
      Text(reference.lastOpened, format: .relative(presentation: .named))
        .foregroundStyle(.secondary)
        .font(.caption)
    }
    .padding(.vertical, 2)
  }
}

/// Where a recent logbook is, in words for LogTen's own logbook and as a path otherwise.
private struct PathLine: View {
  let path: String
  let isDefaultLogbook: Bool

  var body: some View {
    if isDefaultLogbook {
      Text("LogTen Pro’s default logbook")
    } else {
      // swiftlint:disable:next legacy_objc_type
      Text((path as NSString).abbreviatingWithTildeInPath)
    }
  }
}

#Preview("With Recents") {
  OpenLogbookView()
    .environment(PreviewHelper.library(recents: [PreviewHelper.recentReference]))
}

#Preview("No Recents") {
  OpenLogbookView()
    .environment(PreviewHelper.library())
}
