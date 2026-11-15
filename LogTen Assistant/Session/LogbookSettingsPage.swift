import Foundation

/// A page of the Logbook Settings sheet.
nonisolated enum LogbookSettingsPage: String, CaseIterable, Identifiable, Sendable {
  /// The pilot's certificates, ratings and home time zone.
  case pilot
  /// How LogTen's custom fields map to what the checks read.
  case customFields
  /// Settings for each of the logbook's aircraft.
  case aircraft
  /// Which regulations and checks run, and their tolerances.
  case rules

  var id: Self { self }

  /// The page's name in the sheet's segmented control.
  var title: String {
    switch self {
      case .pilot: String(localized: "Pilot")
      case .customFields: String(localized: "Custom Fields")
      case .aircraft: String(localized: "Aircraft")
      case .rules: String(localized: "Rules")
    }
  }
}
