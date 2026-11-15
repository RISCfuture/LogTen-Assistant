import Foundation
import Sentry

/// Crash and error reporting for a shipped launch.
///
/// A logbook holds a pilot's name, certificate numbers, tail numbers, airports and the paths of
/// the folders it lives in, so nothing the SDK collects leaves the Mac unredacted:
/// `sendDefaultPii` stays off, breadcrumbs keep only their category and level, and every event
/// string passes through ``ReportRedaction``.
nonisolated enum CrashReporting {
  /// The project's Sentry DSN, which is write-only: it authorizes sending an event and nothing
  /// else.
  private static let dsn =
    "https://36857d1a2d57dd85ec0bd37a7cd2d888@o4510156629475328.ingest.us.sentry.io/4512433352278017"

  /// How much work is traced and profiled.
  private static let performanceSampleRate: Float = 0.2

  /// Whether this build reports at all. A debug build's hangs come from the debugger, and
  /// previews and tests have no telemetry worth sending.
  private static var reports: Bool {
    #if DEBUG
      false
    #else
      LaunchEnvironment.allowsBackgroundNetworking
    #endif
  }

  /// Starts reporting, unless this launch is a debug build, a preview or a UI test.
  static func start() {
    guard reports else { return }
    SentrySDK.start { options in configure(options) }
  }

  private static func configure(_ options: Sentry.Options) {
    options.dsn = dsn
    options.debug = false
    options.sendDefaultPii = false
    options.tracesSampleRate = NSNumber(value: performanceSampleRate)
    options.configureProfiling = {
      $0.sessionSampleRate = performanceSampleRate
      $0.lifecycle = .trace
    }
    options.beforeSend = { ReportRedaction.redacting($0) }
    options.beforeBreadcrumb = { ReportRedaction.redacting($0) }
  }
}
