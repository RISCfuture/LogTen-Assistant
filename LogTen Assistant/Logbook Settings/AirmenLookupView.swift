import LogbookModel
import PilotLookup
import SwiftUI
import UniformTypeIdentifiers

/// Looks the pilot up in the FAA airmen database and, once the user confirms a match, replaces
/// the certificate settings with the certificates the FAA lists.
struct AirmenLookupView: View {
  private static let spacingBetweenGroups: CGFloat = 16

  @Binding var pilot: PilotProfile

  @Environment(\.dismiss)
  private var dismiss
  @State private var model: AirmenLookupModel
  @State private var selection: AirmanMatch.ID?
  @State private var isChoosingFolder = false

  private var selectedMatch: AirmanMatch? {
    guard case .results(let matches) = model.phase else { return nil }
    return matches.first { $0.id == selection }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Self.spacingBetweenGroups) {
      VStack(alignment: .leading) {
        Text("Look Up in FAA Airmen Database")
          .font(.headline)
        Text(
          "Search the FAA’s releasable airmen database by name. The database is large, so downloading and searching it can take several minutes."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      VStack(alignment: .leading) {
        AirmanNameFields(model: model)
        HStack {
          Button("Download and Search") {
            Task { await model.downloadAndSearch() }
          }
          .disabled(!model.canSearch)
          .accessibilityIdentifier("airmen.download")
          Button("Search Downloaded Database…") { isChoosingFolder = true }
            .disabled(!model.canSearch)
            .accessibilityIdentifier("airmen.chooseFolder")
        }
      }
      AirmenLookupResults(phase: model.phase, selection: $selection)
        .frame(minHeight: 200, maxHeight: .infinity)
    }
    .padding()
    .frame(width: 520, height: 480)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Use Certificates") {
          if let selectedMatch { pilot = selectedMatch.certificates.applied(to: pilot) }
          dismiss()
        }
        .disabled(selectedMatch == nil)
        .accessibilityIdentifier("airmen.apply")
      }
    }
    .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
      guard case .success(let folder) = result else { return }
      Task { await model.search(in: folder) }
    }
  }

  /// Creates the lookup for a pilot profile.
  init(pilot: Binding<PilotProfile>, model: AirmenLookupModel = AirmenLookupModel()) {
    _pilot = pilot
    _model = State(initialValue: model)
  }
}

/// The first and last name to search for.
private struct AirmanNameFields: View {
  @Bindable var model: AirmenLookupModel

  var body: some View {
    HStack {
      TextField("First Name", text: $model.firstName)
        .accessibilityIdentifier("airmen.firstName")
      TextField("Last Name", text: $model.lastName)
        .accessibilityIdentifier("airmen.lastName")
    }
    .textFieldStyle(.roundedBorder)
  }
}

/// The progress or results of a lookup.
private struct AirmenLookupResults: View {
  let phase: AirmenLookupModel.Phase
  @Binding var selection: AirmanMatch.ID?

  var body: some View {
    switch phase {
      case .idle:
        ContentUnavailableView(
          "Enter a Name",
          systemImage: "person.text.rectangle",
          description: Text("Matches from the FAA database appear here.")
        )
      case .downloading:
        ProgressView("Downloading the airmen database…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .searching:
        ProgressView("Searching the airmen database…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .results(let matches) where matches.isEmpty:
        ContentUnavailableView.search
      case .results(let matches):
        List(matches, selection: $selection) { match in
          AirmanMatchRow(match: match)
        }
        .accessibilityIdentifier("airmen.results")
      case .failed(let message):
        ContentUnavailableView(
          "Lookup Failed",
          systemImage: "exclamationmark.triangle",
          description: Text(message)
        )
    }
  }
}

/// One matching airman.
private struct AirmanMatchRow: View {
  let match: AirmanMatch

  var body: some View {
    VStack(alignment: .leading) {
      Text(match.name)
      if let location = match.location {
        Text(location).foregroundStyle(.secondary)
      }
      Text(match.summary)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Idle") {
  @Previewable @State var pilot = PilotProfile()
  AirmenLookupView(pilot: $pilot)
}

#Preview("Searching") {
  @Previewable @State var pilot = PilotProfile()
  AirmenLookupView(pilot: $pilot, model: AirmenLookupModel(phase: .searching))
}

#Preview("Results") {
  @Previewable @State var pilot = PilotProfile()
  AirmenLookupView(pilot: $pilot, model: AirmenLookupModel(phase: .results(PreviewHelper.airmen)))
}
