import SwiftUI
import Tracks

/// Settings ▸ Track Detection: the thresholds that find takeoffs, landings and block movement in
/// ADS-B tracks. Aircraft can override them in Logbook Settings.
struct TrackDetectionSettingsView: View {
  private static let defaults = TrackDetectionSettings()

  @AppStorage(AppSettingsKey.trackAirborneKts)
  private var airborneKts = defaults.airborneKts
  @AppStorage(AppSettingsKey.trackGroundKts)
  private var groundKts = defaults.groundKts
  @AppStorage(AppSettingsKey.trackConfirmSeconds)
  private var confirmSeconds =
    defaults.confirmSeconds
  @AppStorage(AppSettingsKey.trackStopSeconds)
  private var stopSeconds = defaults.stopSeconds
  @AppStorage(AppSettingsKey.trackGapSeconds)
  private var gapSeconds = defaults.gapSeconds

  private var isDefault: Bool {
    airborneKts == Self.defaults.airborneKts && groundKts == Self.defaults.groundKts
      && confirmSeconds == Self.defaults.confirmSeconds
      && stopSeconds == Self.defaults.stopSeconds && gapSeconds == Self.defaults.gapSeconds
  }

  var body: some View {
    Form {
      Section("Speeds") {
        ThresholdField("Airborne at or above", value: $airborneKts, unit: UnitSpeed.knots)
          .accessibilityIdentifier("settings.track.airborne")
        ThresholdField("On the ground at or below", value: $groundKts, unit: UnitSpeed.knots)
          .accessibilityIdentifier("settings.track.ground")
      }
      Section {
        ThresholdField(
          "Confirm a takeoff or landing after",
          value: $confirmSeconds,
          unit: UnitDuration.seconds
        )
        .accessibilityIdentifier("settings.track.confirm")
        ThresholdField(
          "End movement after stopped for",
          value: $stopSeconds,
          unit: UnitDuration.seconds
        )
        .accessibilityIdentifier("settings.track.stop")
        ThresholdField(
          "Split tracks at gaps longer than",
          value: $gapSeconds,
          unit: UnitDuration.seconds
        )
        .accessibilityIdentifier("settings.track.gap")
      } header: {
        Text("Timing")
      } footer: {
        HStack(alignment: .firstTextBaseline) {
          Text("Aircraft can override these in Logbook Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Restore Defaults", action: restoreDefaults)
            .disabled(isDefault)
            .accessibilityIdentifier("settings.track.restoreDefaults")
        }
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func restoreDefaults() {
    airborneKts = Self.defaults.airborneKts
    groundKts = Self.defaults.groundKts
    confirmSeconds = Self.defaults.confirmSeconds
    stopSeconds = Self.defaults.stopSeconds
    gapSeconds = Self.defaults.gapSeconds
  }
}

extension Dimension {
  /// The unit's symbol as pilots write it: “kt” for knots, where `Measurement` formatting
  /// abbreviates them “kn”.
  var aviationSymbol: String {
    self == UnitSpeed.knots ? String(localized: "kt") : symbol
  }
}

/// A numeric threshold with its unit.
private struct ThresholdField<UnitType: Dimension>: View {
  let title: LocalizedStringKey
  @Binding var value: Double
  let unit: UnitType

  @ScaledMetric private var fieldWidth = 70.0
  @ScaledMetric private var unitWidth = 16.0

  var body: some View {
    LabeledContent(title) {
      HStack {
        TextField(title, value: $value, format: .number)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: fieldWidth)
        Text(unit.aviationSymbol)
          .foregroundStyle(.secondary)
          .frame(width: unitWidth, alignment: .leading)
      }
    }
  }

  init(_ title: LocalizedStringKey, value: Binding<Double>, unit: UnitType) {
    self.title = title
    _value = value
    self.unit = unit
  }
}

#Preview("Track Detection") {
  SettingsPanePreview { TrackDetectionSettingsView() }
}
