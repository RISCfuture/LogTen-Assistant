import Audit
import AuditWorkflow
import Corrections
import FlightSources
import Foundation
import LogbookModel
import Review
import Tracks

/// Display names for audit rules. Consistency rules take theirs from the consistency catalog.
nonisolated enum RuleDisplay {
  private static let customPrefix = "custom."

  private static let titles: [String: String.LocalizationValue] = [
    "group_instrument_tracking": "Instrument Group: Tracking",
    "group_instrument_recovery": "Instrument Group: Recovery",
    "group_passenger_window": "Passenger Group: Window",
    "group_night_full_stops": "Night Group: Full Stops",
    "group_review_alternatives": "Flight Review Group: Alternatives",
    "group_6158_windows": "61.58 Group: Windows",
    "unmatched_telemetry": "Unmatched Flight",
    "ambiguous_correlation": "Ambiguous Match",
    "telemetry_time": "Time Differs",
    "telemetry_count": "Count Differs",
    "telemetry_source_conflict": "Sources Disagree",
    "telemetry_missing_times": "Missing Times",
    "telemetry_night_time": "Night Time Differs",
    "telemetry_night_event": "Night Takeoffs or Landings Differ",
    "telemetry_night_full_stops": "Night Full Stops Differ",
    "telemetry_airport": "Airport Differs",
    "telemetry_intermediate_stop": "Unlogged Stop",
    "telemetry_flight_date": "Date Differs",
    "telemetry_distance": "Distance Differs",
    "telemetry_atp_cross_country_candidate": "ATP Cross-Country Candidate",
    "telemetry_atp_cross_country_ineligible": "ATP Cross-Country Ineligible",
    "telemetry_approach_corroboration": "Approach Not Seen",
    "telemetry_approach_detail": "Approach Detail",
    "telemetry_hold_candidates": "Possible Hold",
    "telemetry_navigation_coverage": "Navigation Coverage",
    "reference_unavailable": "Airport Data Unavailable",
    "reference_date": "Airport Data Out of Date",
    "airport_unmatched": "Unknown Airport",
    "airport_timezone": "Airport Time Zone",
    "airport_position": "Airport Position",
    "airport_elevation": "Airport Elevation",
    "timezone_unavailable": "Time Zone Unavailable"
  ]

  /// Every audit rule the app names besides the consistency rules, ordered by title, for
  /// turning rules on and off.
  static var auditRules: [RuleID] {
    titles.keys.map { RuleID(rawValue: $0) }.sorted { title(of: $0) < title(of: $1) }
  }

  /// A rule's title, such as “Time Differs”.
  static func title(of rule: RuleID) -> String {
    if let consistency = ConsistencyRule(id: rule) { return consistency.title }
    if let title = titles[rule.rawValue] { return String(localized: title) }
    if rule.rawValue.hasPrefix(customPrefix) {
      return String(localized: "Custom Rule \(String(rule.rawValue.dropFirst(customPrefix.count)))")
    }
    return rule.rawValue.replacing("_", with: " ").capitalized
  }
}

nonisolated extension AuditPage {
  /// The review queue the page shows, if it is one.
  var queue: ReviewQueue? {
    switch self {
      case .logbookConsistency: .logbookConsistency
      case .aircraftComparisons: .aircraftComparisons
      case .unmatchedActivity: .unmatchedActivity
      case .groupsAndCurrency: .groupsAndCurrency
      case .dataSources, .approved, .appliedHistory: nil
    }
  }
}

nonisolated extension ReviewDecision {
  var title: String {
    switch self {
      case .unreviewed: String(localized: "Unreviewed")
      case .correction: String(localized: "Correction")
      case .falsePositive: String(localized: "Kept as Logged")
      case .needsEvidence: String(localized: "Needs Evidence")
    }
  }

  /// The decision as the inspector states it, such as “Marked for correction”.
  var statusTitle: String {
    switch self {
      case .unreviewed: String(localized: "Not reviewed")
      case .correction: String(localized: "Marked for correction")
      case .falsePositive: String(localized: "Kept as logged")
      case .needsEvidence: String(localized: "Needs more evidence")
    }
  }

  /// The name of the command that makes the decision, for the Undo menu item.
  var actionName: String {
    switch self {
      case .unreviewed: String(localized: "Reset Decision")
      case .correction: String(localized: "Mark for Correction")
      case .falsePositive: String(localized: "Keep as Logged")
      case .needsEvidence: String(localized: "Needs More Evidence")
    }
  }

  var systemImage: String {
    switch self {
      case .unreviewed: "circle"
      case .correction: "pencil.circle.fill"
      case .falsePositive: "checkmark.circle"
      case .needsEvidence: "questionmark.circle"
    }
  }
}

nonisolated extension ReviewReason {
  var title: String {
    switch self {
      case .evidenceConfirms: String(localized: "The evidence confirms it")
      case .logbookCorrect: String(localized: "The logbook is right")
      case .attribution: String(localized: "Another pilot’s flight or partial credit")
      case .evidenceUnreliable: String(localized: "The evidence is unreliable")
      case .other: String(localized: "Other")
    }
  }
}

nonisolated extension Severity {
  var title: String {
    switch self {
      case .suggestion: String(localized: "Suggestion")
      case .questionable: String(localized: "Questionable")
      case .discrepancy: String(localized: "Discrepancy")
    }
  }

  var systemImage: String {
    switch self {
      case .suggestion: "lightbulb"
      case .questionable: "exclamationmark.triangle.fill"
      case .discrepancy: "xmark.octagon.fill"
    }
  }
}

nonisolated extension AuditScope {
  var title: String {
    switch self {
      case .last90Days: String(localized: "Last 90 Days")
      case .thisYear: String(localized: "This Year")
      case .all: String(localized: "All Flights")
    }
  }
}

nonisolated extension EvidenceSource {
  var title: String {
    switch self {
      case .flySto: String(localized: "FlySto")
      case .adsbLol: String(localized: "ADS-B")
      case .openSky: String(localized: "OpenSky")
    }
  }
}

nonisolated extension ObservedField {
  var title: String {
    switch self {
      case .time(let kind): kind.title
      case .count(.takeoff): String(localized: "Takeoffs")
      case .count(.landing): String(localized: "Landings")
      case .count(.fullStop): String(localized: "Full Stops")
    }
  }
}

nonisolated extension FlyStoTimeKind {
  var title: String {
    switch self {
      case .startup: String(localized: "Engine Start")
      case .out: String(localized: "Out")
      case .takeoff: String(localized: "Takeoff")
      case .landing: String(localized: "Landing")
      case .in: String(localized: "In")
      case .shutdown: String(localized: "Engine Stop")
    }
  }
}

nonisolated extension TrackEvent.Kind {
  var title: String {
    switch self {
      case .takeoff: String(localized: "Takeoff")
      case .landing: String(localized: "Landing")
      case .fullStop: String(localized: "Full Stop")
      case .touchAndGo: String(localized: "Touch and Go")
      case .out: String(localized: "Out")
      case .in: String(localized: "In")
      case .groundStop: String(localized: "Ground Stop")
      case .gap: String(localized: "Coverage Gap")
    }
  }
}

nonisolated extension ApplyJournalEntry.Status {
  var title: String {
    switch self {
      case .delivered: String(localized: "Awaiting Verification")
      case .verified: String(localized: "Verified")
      case .failed: String(localized: "Verification Failed")
    }
  }
}

nonisolated extension LogbookFormat {
  private static let minuteFields: Set<LogTenFieldKey> = [
    .flightTotalTime, .flightNight, .flightPIC, .flightSIC, .flightCrossCountry,
    .flightActualInstrument, .flightSimulatedInstrument, .flightDualGiven, .flightDualReceived,
    .flightSolo, .flightSimulator, .flightGround, .flightNightVisionGoggle, .flightPICNight,
    .flightSICNight, .flightDualReceivedNight, .flightP1US, .flightP1USNight,
    .flightCrossCountryNight
  ]

  private static let fieldTitles: [LogTenFieldKey: String.LocalizationValue] = [
    .flightDate: "Date",
    .flightOnDutyTime: "On Duty",
    .flightOffDutyTime: "Off Duty",
    .flightNightVisionGoggle: "NVG",
    .flightNightVisionGoggleTakeoffs: "NVG Takeoffs",
    .flightNightVisionGoggleLandings: "NVG Landings",
    .flightReview: "Flight Review",
    .flightInstrumentProficiencyCheck: "IPC",
    .flightTotalTime: "Total Time",
    .flightPIC: "PIC",
    .flightSIC: "SIC",
    .flightPICNight: "PIC Night",
    .flightSICNight: "SIC Night",
    .flightP1US: "P1 u/s",
    .flightP1USNight: "P1 u/s Night",
    .flightDualReceived: "Dual Received",
    .flightDualReceivedNight: "Dual Received Night",
    .flightCrossCountry: "Cross-Country",
    .flightCrossCountryNight: "Cross-Country Night",
    .flightActualDepartureTime: "Out",
    .flightTakeoffTime: "Off",
    .flightLandingTime: "On",
    .flightActualArrivalTime: "In",
    .flightHobbsStart: "Hobbs Out",
    .flightHobbsStop: "Hobbs In",
    .flightTachStart: "Tach Out",
    .flightTachStop: "Tach In"
  ]

  /// A field's value as an audit shows it: a Zulu time, a duration, a count or text; “—” when
  /// unset.
  static func auditValue(_ value: FieldValue, of field: LogTenFieldKey) -> String {
    switch value {
      case .null: String(localized: "—")
      case .date(let date): zuluTime(date)
      case .integer(let number) where Self.isMinutes(field): duration(minutes: UInt(max(0, number)))
      case .integer(let number): number.formatted(.number)
      case .number(let number): number.formatted(.number.precision(.fractionLength(0...1)))
      case .boolean(let flag): flag ? String(localized: "Yes") : String(localized: "No")
      case .text(let text): text
    }
  }

  /// A field's value as the inspector shows it, or `nil` when it is unset. Unless `explicit`,
  /// zero, false and empty text are unset too; an explicit value, such as one a correction
  /// writes, shows them as “0”, “No” and so on, so only a cleared value reads as unset.
  static func detailValue(
    _ value: FieldValue,
    of field: LogTenFieldKey,
    explicit: Bool = false
  ) -> String? {
    switch value {
      case .null: nil
      case .text(let text) where text.isEmpty: nil
      case .integer(0), .number(0), .boolean(false): explicit ? auditValue(value, of: field) : nil
      default: auditValue(value, of: field)
    }
  }

  /// A field's title: the logbook's own name for a custom field, LogTen's name for a common
  /// field, otherwise one made from the attribute name.
  static func fieldTitle(_ field: LogTenFieldKey, customFields: [CustomFieldDefinition]) -> String {
    if let custom = customFields.first(where: { $0.key == field }) { return custom.title }
    if let title = fieldTitles[field] { return String(localized: title) }
    let name = String(field.attributeName)
    return name.unicodeScalars.reduce(into: "") { title, scalar in
      if CharacterSet.uppercaseLetters.contains(scalar), !title.isEmpty { title += " " }
      title.unicodeScalars.append(scalar)
    }
    .capitalized
  }

  private static func isMinutes(_ field: LogTenFieldKey) -> Bool {
    field.customSlot?.kind == .flightTime || minuteFields.contains(field)
  }
}

nonisolated extension VerificationIssue {
  var explanation: String {
    switch self {
      case .flightsAdded(let ids):
        String(localized: "\(ids.count, format: .number) entries appeared in the logbook.")
      case .flightsRemoved(let ids):
        String(localized: "\(ids.count, format: .number) entries disappeared from the logbook.")
      case .batchFlightProtected(let id):
        String(localized: "Entry \(id.rawValue) is now locked or signed.")
      case .flightKeyChanged(let id):
        String(localized: "Entry \(id.rawValue)’s flight key changed.")
      case .flightKeyNotUnique(let id):
        String(localized: "Entry \(id.rawValue)’s flight key is no longer unique.")
      case let .unexpectedValue(id, field, expected, found):
        String(
          localized:
            "Entry \(id.rawValue)’s \(field.rawValue) is \(LogbookFormat.auditValue(found, of: field)), not \(LogbookFormat.auditValue(expected, of: field))."
        )
      case .crewOrApproachesChanged(let id):
        String(localized: "Entry \(id.rawValue)’s crew, passengers or approaches changed.")
      case .signatureChanged(let id):
        String(localized: "Entry \(id.rawValue) was signed or lost its signature.")
    }
  }
}
