import SwiftUI

/// A sheet crediting the Swift packages and data sources the app builds on, opened from the
/// About window.
struct AcknowledgementsSheet: View {
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        AcknowledgementsSection(title: "Swift Packages", entries: Acknowledgement.packages)
        AcknowledgementsSection(title: "Data Sources", entries: Acknowledgement.dataSources)
      }
      .formStyle(.grouped)
      .navigationTitle("Acknowledgements")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("about.acknowledgements.done")
        }
      }
    }
    .frame(width: 460, height: 460)
  }
}

private struct AcknowledgementsSection: View {
  let title: LocalizedStringKey
  let entries: [Acknowledgement]

  var body: some View {
    Section(title) {
      ForEach(entries) { entry in
        LabeledContent {
          Text(entry.license)
        } label: {
          Link(entry.name, destination: entry.url)
        }
      }
    }
  }
}

#Preview("Acknowledgements") {
  AcknowledgementsSheet()
}
