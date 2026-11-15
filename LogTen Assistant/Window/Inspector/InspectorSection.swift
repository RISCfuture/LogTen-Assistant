import AppKit
import SwiftUI

/// The scrolling page of an inspector, its sections stacked edge to edge like LogTen's.
struct InspectorPage<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) { content }
    }
    .textSelection(.enabled)
    .inspectorTextSize()
  }
}

/// The small text and controls of LogTen's inspector.
struct InspectorTextSize: ViewModifier {
  @ScaledMetric(relativeTo: .body)
  private var size = NSFont.smallSystemFontSize

  func body(content: Content) -> some View {
    content
      .font(.system(size: size))
      .controlSize(.small)
  }
}

extension View {
  /// Sets the small text and controls of LogTen's inspector.
  func inspectorTextSize() -> some View {
    modifier(InspectorTextSize())
  }
}

/// A section of an inspector page, under a full-width header bar like LogTen's.
struct InspectorSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    Section {
      VStack(alignment: .leading) { content }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    } header: {
      InspectorSectionHeader(title: title)
    }
  }

  /// Creates a section with a title, which the header shows in capitals.
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
}

/// A section's header: its title in capitals on a full-width bar, opaque so it stays legible
/// while it pins over the section's scrolling content.
struct InspectorSectionHeader: View {
  private static let verticalPadding = 4.0

  let title: String

  @ScaledMetric(relativeTo: .title3)
  private var size = NSFont.systemFontSize

  var body: some View {
    Text(title)
      .font(.system(size: size))
      .textCase(.uppercase)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, Self.verticalPadding)
      .background(.fill.tertiary)
      .background(.background)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A heading within an inspector section, such as a finding's rule or “Recommendation”.
struct InspectorSubheading: View {
  let title: String

  var body: some View {
    Text(title)
      .fontWeight(.semibold)
      .accessibilityAddTraits(.isHeader)
  }

  /// Creates a heading.
  init(_ title: String) {
    self.title = title
  }
}

#Preview("Sections") {
  InspectorColumnPreview {
    InspectorPage {
      InspectorSection("Checks") {
        InspectorSubheading("Seat Time")
        Text(verbatim: "PIC 1.0 and SIC 1.0 are logged.")
      }
      InspectorSection("Flight") {
        Text(verbatim: "N2468P")
      }
    }
  }
}
