import LogbookModel
import SwiftUI
import Tracks

/// Logbook Settings ▸ Aircraft: what the app knows about each aircraft that the logbook doesn't.
struct AircraftSettingsView: View {
  @Binding var aircraft: [String: AircraftSettings]
  let registrations: [String]

  /// The Rules ▸ Tolerances value that an aircraft's own longest plausible flight overrides.
  let defaultMaximumFlightMinutes: UInt

  @State private var selection: String?

  var body: some View {
    HSplitView {
      List(registrations, id: \.self, selection: $selection) { registration in
        Text(registration)
          .accessibilityIdentifier("aircraftSettings.\(registration)")
      }
      .frame(minWidth: 140, idealWidth: 160, maxWidth: 220)
      .accessibilityIdentifier("aircraftSettings.list")
      if let selection {
        AircraftForm(
          registration: selection,
          defaultMaximumFlightMinutes: defaultMaximumFlightMinutes,
          settings: binding(for: selection)
        )
      } else {
        ContentUnavailableView(
          "No Aircraft Selected",
          systemImage: "airplane",
          description: Text("Select an aircraft to change its settings.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task { selection = selection ?? registrations.first }
  }

  private func binding(for registration: String) -> Binding<AircraftSettings> {
    Binding {
      aircraft[registration] ?? AircraftSettings()
    } set: { settings in
      aircraft[registration] = settings == AircraftSettings() ? nil : settings
    }
  }
}

/// One aircraft's settings.
private struct AircraftForm: View {
  private static let minutesPerHour = 60.0

  private static let globalDefaults = TrackDetectionSettings()

  let registration: String
  let defaultMaximumFlightMinutes: UInt
  @Binding var settings: AircraftSettings

  @AppStorage(AppSettingsKey.trackAirborneKts)
  private var globalAirborneKts = globalDefaults.airborneKts
  @AppStorage(AppSettingsKey.trackGroundKts)
  private var globalGroundKts = globalDefaults.groundKts
  @AppStorage(AppSettingsKey.trackConfirmSeconds)
  private var globalConfirmSeconds = globalDefaults.confirmSeconds
  @AppStorage(AppSettingsKey.trackStopSeconds)
  private var globalStopSeconds = globalDefaults.stopSeconds
  @AppStorage(AppSettingsKey.trackGapSeconds)
  private var globalGapSeconds = globalDefaults.gapSeconds

  private var defaultMaximumHours: Measurement<UnitDuration> {
    Measurement(value: Double(defaultMaximumFlightMinutes), unit: UnitDuration.minutes)
      .converted(to: .hours)
  }

  private var aliases: Binding<String> {
    Binding {
      settings.aliases.joined(separator: ", ")
    } set: { text in
      settings.aliases = text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }
  }

  private var icaoAddress: Binding<String> {
    Binding {
      settings.icaoAddress?.hex.uppercased() ?? ""
    } set: { text in
      settings.icaoAddress = ICAOAddress(hex: text.trimmingCharacters(in: .whitespaces))
    }
  }

  private var maximumHours: Binding<Double?> {
    Binding {
      settings.maximumFlightTime.map { Double($0) / Self.minutesPerHour }
    } set: { hours in
      settings.maximumFlightTime = hours.map { UInt(max(0, $0 * Self.minutesPerHour)) }
    }
  }

  private var ifrCapability: Binding<IFRCapability> {
    Binding {
      IFRCapability(settings.isIFRCapable)
    } set: { capability in
      settings.isIFRCapable = capability.value
    }
  }

  var body: some View {
    Form {
      Section("Identity") {
        TextField("Other Registrations", text: aliases, prompt: Text("N12345, C-GABC"))
          .accessibilityIdentifier("aircraftSettings.aliases")
        TextField("ICAO Address", text: icaoAddress, prompt: Text("Derived from the N-number"))
          .monospaced()
          .accessibilityIdentifier("aircraftSettings.icaoAddress")
        TextField("FlySto Aircraft ID", text: optionalText(\.flyStoAircraftID))
      }
      Section("Checks") {
        Picker("IFR Capable", selection: ifrCapability) {
          ForEach(IFRCapability.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        TextField("Type Rating", text: optionalText(\.typeRating), prompt: Text("None"))
        Toggle("Requires a 61.58 proficiency check", isOn: $settings.requiresProficiencyCheck)
        TextField(
          "Longest Plausible Flight Override",
          value: maximumHours,
          format: .number,
          prompt: Text("Default: \(defaultMaximumHours, format: .measurement(width: .abbreviated))")
        )
        Toggle(
          "Ignore unmatched ADS-B activity (shared aircraft)",
          isOn: $settings.ignoresUnmatchedActivity
        )
        .accessibilityIdentifier("aircraftSettings.ignoresUnmatched")
      }
      Section("Track Detection") {
        OverrideField(
          title: "Airborne at or above",
          unit: UnitSpeed.knots,
          defaultValue: globalAirborneKts,
          value: $settings.trackDetection.airborneSpeedKts
        )
        OverrideField(
          title: "On the ground at or below",
          unit: UnitSpeed.knots,
          defaultValue: globalGroundKts,
          value: $settings.trackDetection.groundSpeedKts
        )
        OverrideField(
          title: "Confirm a takeoff or landing after",
          unit: UnitDuration.seconds,
          defaultValue: globalConfirmSeconds,
          value: $settings.trackDetection.confirmSeconds
        )
        OverrideField(
          title: "End movement after stopped for",
          unit: UnitDuration.seconds,
          defaultValue: globalStopSeconds,
          value: $settings.trackDetection.stopSeconds
        )
        OverrideField(
          title: "Split tracks at gaps longer than",
          unit: UnitDuration.seconds,
          defaultValue: globalGapSeconds,
          value: $settings.trackDetection.gapSeconds
        )
      }
      Section("Simulator Credit") {
        ForEach(SimulatorCredit.allCases, id: \.self) { credit in
          Toggle(credit.title, isOn: creditBinding(credit))
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(registration)
  }

  private func optionalText(_ keyPath: WritableKeyPath<AircraftSettings, String?>) -> Binding<
    String
  > {
    Binding {
      settings[keyPath: keyPath] ?? ""
    } set: { text in
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      settings[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
    }
  }

  private func creditBinding(_ credit: SimulatorCredit) -> Binding<Bool> {
    Binding {
      settings.simulatorCredit.contains(credit)
    } set: { isOn in
      if isOn {
        settings.simulatorCredit.insert(credit)
      } else {
        settings.simulatorCredit.remove(credit)
      }
    }
  }
}

/// A track-detection threshold that falls back to the global setting when empty, and shows
/// the global setting as its prompt.
private struct OverrideField<UnitType: Dimension>: View {
  let title: LocalizedStringKey
  let unit: UnitType
  let defaultValue: Double
  @Binding var value: Double?

  var body: some View {
    LabeledContent(title) {
      HStack {
        TextField(
          title,
          value: $value,
          format: .number,
          prompt: Text("Default: \(defaultValue, format: .number) \(unit.aviationSymbol)")
        )
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        Text(unit.aviationSymbol).foregroundStyle(.secondary)
      }
    }
  }
}

/// Whether an aircraft is IFR capable, including not knowing.
private enum IFRCapability: CaseIterable {
  case unknown
  case capable
  case notCapable

  var value: Bool? {
    switch self {
      case .unknown: nil
      case .capable: true
      case .notCapable: false
    }
  }

  var title: String {
    switch self {
      case .unknown: String(localized: "Unknown")
      case .capable: String(localized: "Yes")
      case .notCapable: String(localized: "No")
    }
  }

  init(_ value: Bool?) {
    switch value {
      case nil: self = .unknown
      case true?: self = .capable
      case false?: self = .notCapable
    }
  }
}

nonisolated extension SimulatorCredit {
  var title: String {
    switch self {
      case .instrumentExperience: String(localized: "Instrument experience (61.57(c))")
      case .instrumentProficiencyCheck: String(localized: "Instrument proficiency check (61.57(d))")
      case .takeoffsAndLandings: String(localized: "Takeoffs and landings (61.57(a), (b))")
      case .flightReview: String(localized: "Flight review (61.56)")
      case .proficiencyCheck: String(localized: "Proficiency check (61.58)")
    }
  }
}

#Preview("In Logbook Settings", traits: .sampleSession { $0.logbookSettingsPage = .aircraft }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}
