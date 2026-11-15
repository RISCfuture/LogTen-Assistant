import AppKit
import SwiftUI

/// Settings ▸ Data: where downloaded reference and ADS-B data is kept.
struct DataSettingsView: View {
  private static let cacheLimitsGB = [1, 5, 10, 25, 50]

  @AppStorage(AppSettingsKey.adsbCacheLimitGB)
  private var cacheLimitGB = 10
  @AppStorage(AppSettingsKey.updatesNASRAutomatically)
  private var updatesNASRAutomatically = true

  var body: some View {
    Form {
      Section("ADS-B Downloads") {
        LabeledContent {
          Button("Show in Finder", action: showCache)
        } label: {
          Text("Location")
          Text(SessionServices.adsbCacheDirectory.path(percentEncoded: false))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        Picker("Keep up to", selection: $cacheLimitGB) {
          ForEach(Self.cacheLimitsGB, id: \.self) { limit in
            Text(
              Measurement(value: Double(limit), unit: UnitInformationStorage.gigabytes),
              format: .measurement(width: .abbreviated)
            )
            .tag(limit)
          }
        }
        .accessibilityIdentifier("settings.adsbCacheLimit")
      }
      Section("Airport Data") {
        Toggle(isOn: $updatesNASRAutomatically) {
          Text("Update NASR data automatically")
          Text("The FAA publishes new airport and runway data every 28 days.")
        }
        .accessibilityIdentifier("settings.updatesNASR")
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func showCache() {
    let directory = SessionServices.adsbCacheDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([directory])
  }
}

#Preview("Data") {
  SettingsPanePreview { DataSettingsView() }
}
