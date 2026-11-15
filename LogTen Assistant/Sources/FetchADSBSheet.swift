import LogbookModel
import SwiftUI

/// Audit ▸ Fetch ADS-B Data…: choose days and aircraft and confirm the download size, then
/// start the download, which carries on in the background on the Data Sources page.
struct FetchADSBSheet: View {
  @Environment(\.dismiss)
  private var dismiss
  @State private var model: ADSBFetchModel

  private var isChecking: Bool {
    if case .checking = model.phase { true } else { false }
  }

  private var downloadTitle: String {
    guard case .confirming(let estimate) = model.phase, let bytes = estimate.bytes else {
      return String(localized: "Download")
    }
    return String(localized: "Download \(bytes, format: .byteCount(style: .file))")
  }

  private var canDownload: Bool {
    guard case .confirming(let estimate) = model.phase else { return false }
    return !estimate.days.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Fetch ADS-B Data")
        .font(.headline)
        .padding([.top, .horizontal])
      Form {
        Section {
          DatePicker("From", selection: $model.startDate, displayedComponents: .date)
          DatePicker("To", selection: $model.endDate, displayedComponents: .date)
          LabeledContent("Days") { Text(model.days.count, format: .number) }
          FetchStatus(phase: model.phase)
        } footer: {
          Text("Up to a month at a time. Each day’s archive is several gigabytes.")
        }
        .disabled(isChecking)
        Section("Aircraft Flown") {
          if model.aircraft.isEmpty {
            Text(
              "No aircraft with a known ICAO address was flown on these days. Add an address in Logbook Settings ▸ Aircraft."
            )
            .foregroundStyle(.secondary)
          }
          ForEach(model.aircraft, id: \.registration) { aircraft in
            Toggle(isOn: binding(for: aircraft.registration)) {
              Text(aircraft.registration)
              Text(aircraft.address.hex.uppercased()).monospaced()
            }
          }
        }
        .disabled(isChecking)
      }
      .formStyle(.grouped)
    }
    .frame(width: 480)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(isChecking ? "Stop" : "Close") {
          if isChecking { model.cancel() } else { dismiss() }
        }
        .accessibilityIdentifier("fetchADSB.close")
      }
      ToolbarItem(placement: .confirmationAction) {
        if case .confirming = model.phase {
          Button(downloadTitle) {
            if model.startDownload() { dismiss() }
          }
          .disabled(!canDownload)
          .accessibilityIdentifier("fetchADSB.download")
        } else {
          Button("Check Size") { model.checkSize() }
            .disabled(isChecking || !model.canCheckSize)
            .accessibilityIdentifier("fetchADSB.checkSize")
        }
      }
    }
    .onChange(of: model.days) { model.choiceDidChange() }
    .onChange(of: model.selectedRegistrations) { model.choiceDidChange() }
    .onDisappear { model.cancel() }
    .accessibilityIdentifier("fetchADSBSheet")
  }

  /// Creates the sheet for a session's aircraft.
  init(session: LogbookSession) {
    _model = State(initialValue: ADSBFetchModel(session: session))
  }

  private func binding(for registration: String) -> Binding<Bool> {
    Binding {
      model.selectedRegistrations.contains(registration)
    } set: { isOn in
      if isOn {
        model.selectedRegistrations.insert(registration)
      } else {
        model.selectedRegistrations.remove(registration)
      }
    }
  }
}

/// What checking the size found.
private struct FetchStatus: View {
  let phase: ADSBFetchModel.Phase

  var body: some View {
    switch phase {
      case .choosing:
        Text("Check the size before downloading.").foregroundStyle(.secondary)
      case .checking:
        ProgressView("Finding archives…").progressViewStyle(.linear)
      case .confirming(let estimate):
        if estimate.days.isEmpty {
          Text("Every chosen day is already downloaded.")
            .accessibilityIdentifier("fetchADSB.size")
        } else if let bytes = estimate.bytes {
          Text(
            "\(estimate.days.count) archives, \(bytes, format: .byteCount(style: .file))"
          )
          .accessibilityIdentifier("fetchADSB.size")
        } else {
          Text("\(estimate.days.count) archives, size unknown")
            .accessibilityIdentifier("fetchADSB.size")
        }
      case .failed(let reason):
        Label(reason, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("fetchADSB.error")
    }
  }
}

#Preview("Choosing Days", traits: .sampleSession()) {
  @Environment(LogbookSession.self)
  @Previewable var session
  FetchADSBSheet(session: session)
}
