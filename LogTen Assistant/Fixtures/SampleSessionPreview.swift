import SwiftUI

/**
 Gives a preview a loaded session for the sample logbook in its environment.

 The sample logbook is read, checked and audited once, for every preview that uses the
 modifier, before any of them render. Each preview then gets its own copy of that session,
 adjusted by its `prepare` closure before its first frame, so one preview's selection or
 decisions never show in another.

 ```swift
 #Preview(traits: .sampleSession { $0.sidebarSelection = .violations(nil) }) {
   @Environment(LogbookSession.self)
  @Previewable var session
   ViolationsView(session: session, rule: nil)
 }
 ```
 */
struct SampleSessionPreview: PreviewModifier {
  /// Adjusts the preview's copy of the session, such as selecting a page or a flight.
  var prepare: (LogbookSession) -> Void = { _ in }

  /// Loads the session in a task of its own, which finishes the audit even when Xcode cancels
  /// the task that asked for the context.
  static func makeSharedContext() async throws -> LogbookSession {
    let session = PreviewHelper.session()
    await Task { await session.load() }.value
    return session
  }

  func body(content: Content, context: LogbookSession) -> some View {
    PreparedSession(loaded: context, prepare: prepare) { content }
  }
}

/// Puts a prepared copy of a loaded session in its content's environment.
private struct PreparedSession<Content: View>: View {
  @State private var session: LogbookSession
  @ViewBuilder let content: Content

  var body: some View {
    content.environment(session)
  }

  init(
    loaded: LogbookSession,
    prepare: (LogbookSession) -> Void,
    @ViewBuilder content: () -> Content
  ) {
    let session = LogbookSession(copying: loaded)
    prepare(session)
    _session = State(initialValue: session)
    self.content = content()
  }
}

extension PreviewTrait where T == Preview.ViewTraits {
  /**
   Gives the preview a copy of the loaded sample session in its environment.

   - Parameter prepare: Adjusts the session before the preview first renders.
   */
  static func sampleSession(
    _ prepare: @escaping (LogbookSession) -> Void = { _ in }
  ) -> PreviewTrait<T> {
    .modifier(SampleSessionPreview(prepare: prepare))
  }
}
