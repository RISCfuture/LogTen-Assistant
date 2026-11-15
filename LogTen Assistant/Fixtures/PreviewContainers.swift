import SwiftUI

/// The sizes of a logbook window's parts at the window's default size, for previews.
enum PreviewLayout {
  /// The height of the window's toolbar, which the columns sit below.
  private static let toolbarHeight = 52.0

  /// The whole window.
  static let window = LogbookSplitView.defaultWindowSize

  /// The height of each column below the toolbar.
  static let columnHeight = window.height - toolbarHeight

  /// The page column between the sidebar and the inspector.
  static let page = CGSize(
    width: window.width - LogbookSplitView.sidebarIdealWidth
      - LogbookSplitView.inspectorIdealWidth,
    height: columnHeight
  )
}

/// A whole logbook window at its default size.
struct WindowPreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(width: PreviewLayout.window.width, height: PreviewLayout.window.height)
  }
}

/// A page in the window's page column, below its page bar: the page the sidebar selected, or
/// other content.
struct PageColumnPreview<Content: View>: View {
  let session: LogbookSession
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaBar(edge: .top) { PageBar(session: session) }
      .frame(width: PreviewLayout.page.width, height: PreviewLayout.page.height)
      .background(.windowBackground)
  }
}

extension PageColumnPreview where Content == LogbookDetail {
  /// Shows the page the session's sidebar selected.
  init(session: LogbookSession) {
    self.init(session: session) { LogbookDetail(session: session) }
  }
}

/// Rows of a grouped form, such as the Data Sources page's, at the page column's width.
struct PageFormPreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Form { content }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: PreviewLayout.page.width)
  }
}

/// Content in the window's inspector column.
struct InspectorColumnPreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .frame(width: LogbookSplitView.inspectorIdealWidth, height: PreviewLayout.columnHeight)
      .background(.windowBackground)
  }
}

/// Content in the window's sidebar column, which runs the window's full height.
struct SidebarColumnPreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(width: LogbookSplitView.sidebarIdealWidth, height: PreviewLayout.window.height)
  }
}

/// A pane of the Settings window, at the window's width.
struct SettingsPanePreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(width: AppSettingsView.width)
  }
}

/// The contents of a popover, on a popover's background with room around it.
struct PopoverPreview<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(.regularMaterial, in: .rect(cornerRadius: 12))
      .shadow(radius: 8)
      .padding(40)
  }
}
