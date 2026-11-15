import LogbookModel
import SwiftUI

/// Settings for one logbook (⌥⌘,), edited as a draft and saved when the user clicks Done.
struct LogbookSettingsSheet: View {
  let session: LogbookSession

  @Environment(\.dismiss)
  private var dismiss
  @State private var draft: LogbookSettings
  @State private var page: LogbookSettingsPage
  @ScaledMetric private var width = 680.0
  @ScaledMetric private var height = 620.0

  var body: some View {
    VStack(spacing: 0) {
      Text("Logbook Settings")
        .font(.headline)
        .padding([.top, .horizontal])
      Picker("Section", selection: $page) {
        ForEach(LogbookSettingsPage.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .padding()
      .accessibilityIdentifier("logbookSettings.page")
      Divider()
      PageContent(page: page, draft: $draft, session: session)
        .spotlighting(page == session.logbookSettingsPage ? session.spotlitSettings : [])
    }
    .frame(width: width, height: height)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
          .accessibilityIdentifier("logbookSettings.cancel")
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          let settings = draft
          dismiss()
          Task { await session.apply(settings) }
        }
        .accessibilityIdentifier("logbookSettings.done")
      }
    }
    .accessibilityIdentifier("logbookSettingsSheet")
  }

  /// Creates the sheet for a session's settings, opened on the page the session names.
  init(session: LogbookSession) {
    self.session = session
    _draft = State(initialValue: session.settings)
    _page = State(initialValue: session.logbookSettingsPage ?? .pilot)
  }
}

/// The page of the draft that the segmented control selects.
private struct PageContent: View {
  let page: LogbookSettingsPage
  @Binding var draft: LogbookSettings
  let session: LogbookSession

  var body: some View {
    switch page {
      case .pilot:
        PilotSettingsView(pilot: $draft.pilot, people: session.people)
      case .customFields:
        CustomFieldsSettingsView(
          mapping: $draft.fieldMapping,
          customFields: session.logbook?.customFields ?? []
        )
      case .aircraft:
        AircraftSettingsView(
          aircraft: $draft.aircraft,
          registrations: session.registrations,
          defaultMaximumFlightMinutes: draft.rules.tolerances.maximumFlightMinutes
        )
      case .rules:
        RulesSettingsView(
          rules: $draft.rules,
          customFields: session.logbook?.customFields ?? [],
          revealsRegulations: session.spotlitSettings.contains { $0.rule != nil }
        )
    }
  }
}

#Preview("Pilot", traits: .sampleSession()) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}
