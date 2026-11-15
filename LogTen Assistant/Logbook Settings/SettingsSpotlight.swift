import LogbookModel
import Regulations
import SwiftUI

/// A setting that Logbook Settings points out when it opens, because changing it lets a rule
/// run.
nonisolated enum SettingsTarget: Hashable, Sendable {
  /// A custom-field role to map.
  case fieldRole(FieldRole)

  /// A part of the pilot profile.
  case pilot(PilotSetting)

  /// A regulation's on-off switch.
  case rule(RegulationRule)

  /// The regulation whose switch this is, if it is one.
  var rule: RegulationRule? {
    if case .rule(let rule) = self { rule } else { nil }
  }
}

/// A part of the pilot profile that decides whether a rule applies.
nonisolated enum PilotSetting: Hashable, Sendable {
  case certificate
  case ignoresInstructionActivity
  case instrumentRatings
  case instructorRatings
}

extension View {
  /**
   Scrolls to the first of these settings when the page appears and highlights each of them for
   a moment.

   Apply it to the page's scrolling content; mark each setting it can point out with
   ``spotlightTarget(_:)``.
   */
  func spotlighting(_ targets: [SettingsTarget]) -> some View {
    modifier(Spotlighting(targets: targets))
  }

  /// Marks a setting that its page can scroll to and highlight.
  func spotlightTarget(_ target: SettingsTarget) -> some View {
    modifier(SpotlightTarget(target: target))
  }
}

extension EnvironmentValues {
  /// The settings the page is highlighting right now.
  @Entry fileprivate var litSettings = Set<SettingsTarget>()
}

private struct Spotlighting: ViewModifier {
  private static let duration = Duration.seconds(2)

  let targets: [SettingsTarget]

  @State private var lit = Set<SettingsTarget>()

  func body(content: Content) -> some View {
    ScrollViewReader { proxy in
      content
        .environment(\.litSettings, lit)
        .task { await pointOut(scrollingWith: proxy) }
    }
  }

  private func pointOut(scrollingWith proxy: ScrollViewProxy) async {
    guard let first = targets.first else { return }
    proxy.scrollTo(first, anchor: .center)
    lit = Set(targets)
    try? await Task.sleep(for: Self.duration)
    withAnimation(.easeOut(duration: 0.6)) { lit = [] }
  }
}

/// Tints and outlines a setting while its page points it out.
private struct SpotlightTarget: ViewModifier {
  let target: SettingsTarget

  @Environment(\.litSettings)
  private var litSettings

  private var isLit: Bool { litSettings.contains(target) }

  func body(content: Content) -> some View {
    content
      .id(target)
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .fill(.tint.opacity(isLit ? 0.15 : 0))
          .stroke(.tint.opacity(isLit ? 0.6 : 0))
          .padding(-6)
          .allowsHitTesting(false)
      }
  }
}
