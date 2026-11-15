import AppKit
import SwiftUI

/// The identifier of the About window.
enum AboutWindow {
  static let id = "about"
}

/// The custom About window: the app's identity, links, and a button to its acknowledgements.
struct AboutView: View {
  /// The About window is a fixed-size card, so it carries a roomier inset than the default.
  private static let panelInset: CGFloat = 24

  private let info = AppInfo.current
  @State private var isShowingAcknowledgements = false

  var body: some View {
    VStack {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityLabel("LogTen Assistant app icon")

      VStack(spacing: 4) {
        Text(info.name).font(.title2).bold()
        Text("Version \(info.version) (\(info.build))")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(info.copyright)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .textSelection(.enabled)

      Divider()

      Text("Not affiliated with Coradine Aviation Systems. LogTen is a trademark of Coradine.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack {
        Link("Website", destination: AppLinks.website)
          .accessibilityIdentifier("about.website")
        Link("Report an Issue", destination: AppLinks.issues)
          .accessibilityIdentifier("about.reportIssue")
        Button("Acknowledgements…") { isShowingAcknowledgements = true }
          .accessibilityIdentifier("about.acknowledgements")
      }
    }
    .padding(Self.panelInset)
    .frame(width: 380)
    .sheet(isPresented: $isShowingAcknowledgements) {
      AcknowledgementsSheet()
    }
  }
}

#Preview("About") {
  AboutView()
}
