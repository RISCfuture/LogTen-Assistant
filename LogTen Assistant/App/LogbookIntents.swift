import AppIntents
import AuditWorkflow
import Foundation
import Regulations

/// The logbook sessions of the open windows, most recently active last, for App Intents to
/// act on.
final class OpenLogbooks {
  /// The app's open logbooks.
  static let shared = OpenLogbooks()

  private var sessions = [WeakSession]()

  /// The most recently active open logbook.
  var current: LogbookSession? {
    sessions.removeAll { $0.session == nil }
    return sessions.last?.session
  }

  /// Notes that a window's logbook became active.
  func activate(_ session: LogbookSession) {
    sessions.removeAll { $0.session == nil || $0.session === session }
    sessions.append(WeakSession(session: session))
  }

  private struct WeakSession {
    weak var session: LogbookSession?
  }
}

/// Why an intent couldn't run.
enum LogbookIntentError: Error, CustomLocalizedStringResourceConvertible {
  /// No logbook window is open.
  case noOpenLogbook

  var localizedStringResource: LocalizedStringResource {
    switch self {
      case .noOpenLogbook: "Open a logbook in LogTen Assistant first."
    }
  }
}

/// Takes a fresh snapshot of the open logbook and audits it.
struct RunAuditIntent: AppIntent {
  static let title: LocalizedStringResource = "Run Audit"
  static let description = IntentDescription(
    "Takes a fresh snapshot of the open logbook, checks it against the regulations and audits it. Returns the number of findings left to review."
  )

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    guard let session = OpenLogbooks.shared.current else { throw LogbookIntentError.noOpenLogbook }
    await session.runAudit()
    let unreviewed = ReviewQueue.allCases.reduce(0) { count, queue in
      count + session.unreviewedCount(in: FindingList(queue: queue))
    }
    return .result(
      value: unreviewed,
      dialog:
        "\(unreviewed, format: .number) findings in \(session.reference.title) are left to review."
    )
  }
}

/// Counts the regulatory violations in the open logbook.
struct CountViolationsIntent: AppIntent {
  static let title: LocalizedStringResource = "Count Violations"
  static let description = IntentDescription(
    "Returns the number of regulatory violations found in the open logbook."
  )

  @MainActor
  func perform() throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    guard let session = OpenLogbooks.shared.current else { throw LogbookIntentError.noOpenLogbook }
    let count = session.regulationReport?.violations.count ?? 0
    return .result(
      value: count,
      dialog: "\(session.reference.title) has \(count, format: .number) violations."
    )
  }
}

/// The app's Shortcuts phrases.
struct LogbookShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RunAuditIntent(),
      phrases: ["Run an audit in \(.applicationName)", "Audit my logbook with \(.applicationName)"],
      shortTitle: "Run Audit",
      systemImageName: "text.page.badge.magnifyingglass"
    )
    AppShortcut(
      intent: CountViolationsIntent(),
      phrases: ["Count violations in \(.applicationName)"],
      shortTitle: "Count Violations",
      systemImageName: "exclamationmark.triangle"
    )
  }
}
