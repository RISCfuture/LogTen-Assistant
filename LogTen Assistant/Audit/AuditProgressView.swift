import SwiftUI

/// The current step of opening or auditing a logbook: a bar when the step knows how much work
/// it has, otherwise a spinner.
struct AuditProgressView: View {
  private static let barWidth: CGFloat = 280

  let phase: LogbookSession.Phase

  /// How much of the step is done, from 0 to 1, or `nil` if its size isn't known.
  var fraction: Double?

  /// The title to show when the session isn't in a loading step.
  var fallbackTitle = String(localized: "Auditing…")

  private var title: String {
    if case .working(let step) = phase { step.title } else { fallbackTitle }
  }

  var body: some View {
    Group {
      if let fraction {
        ProgressView(value: fraction) {
          Text(title)
        }
        .frame(width: Self.barWidth)
      } else {
        ProgressView(title)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("auditProgress")
  }
}

#Preview("Determinate") {
  AuditProgressView(phase: .working(.reading), fraction: 0.42)
    .frame(width: PreviewLayout.page.width, height: PreviewLayout.page.height)
}

#Preview("Indeterminate") {
  AuditProgressView(phase: .working(.snapshotting))
    .frame(width: PreviewLayout.page.width, height: PreviewLayout.page.height)
}
