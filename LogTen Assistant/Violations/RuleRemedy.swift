import Foundation
import LogbookModel
import Regulations

/// Why a rule didn't run, and the Logbook Settings page that lets it run.
nonisolated struct RuleRemedy: Hashable, Sendable {
  /// The rule that didn't run.
  let rule: RegulationRule

  /// The settings page holding what keeps the rule from running.
  let page: LogbookSettingsPage

  /// The settings the page points out: the unmapped roles the rule reads, the part of the pilot
  /// profile that rules it out, or its own switch.
  let targets: [SettingsTarget]

  /// Why the rule didn't run and what to change, in a sentence or two.
  let description: String

  /// The title of the button that opens the settings page, such as “Map Fields…”.
  var actionTitle: String {
    switch page {
      case .customFields: String(localized: "Map Fields…")
      case .pilot: String(localized: "Edit Pilot Profile…")
      case .rules: String(localized: "Turn On Rule…")
      case .aircraft: String(localized: "Edit Aircraft…")
    }
  }

  /// Creates the remedy for a rule's status, or `nil` if the rule ran.
  init?(rule: RegulationRule, status: RuleStatus) {
    self.rule = rule
    switch status {
      case .evaluated:
        return nil
      case .notEvaluated(let roles):
        page = .customFields
        targets = roles.map(SettingsTarget.fieldRole)
        description = Self.mappingDescription(of: roles)
      case .skipped(let reason):
        page = reason == .disabled ? .rules : .pilot
        targets = [reason.target(for: rule)]
        description = "\(reason.explanation) \(reason.instruction)"
    }
  }

  private static func mappingDescription(of roles: [FieldRole]) -> String {
    let titles = roles.map(\.title).formatted(.list(type: .and))
    return roles.count == 1
      ? String(
        localized:
          "This rule reads a custom field that isn’t mapped. Map a field for \(titles) to check it."
      )
      : String(
        localized:
          "This rule reads custom fields that aren’t mapped. Map fields for \(titles) to check it."
      )
  }
}

nonisolated extension RuleSkipReason {
  /// What to change in Logbook Settings for the rule to run.
  fileprivate var instruction: String {
    switch self {
      case .disabled: String(localized: "Turn it on in the rules settings to check it.")
      case .notFlightInstructor:
        String(localized: "Add a flight instructor rating to the pilot profile to check it.")
      case .ignoresInstructionActivity:
        String(localized: "Turn off “Ignore instruction activity” to check it.")
      case .noInstrumentRating:
        String(localized: "Add an instrument rating to the pilot profile to check it.")
      case .studentPilot:
        String(
          localized: "If the pilot holds a higher certificate, change it in the pilot profile."
        )
    }
  }

  /// The setting to change for the rule to run.
  fileprivate func target(for rule: RegulationRule) -> SettingsTarget {
    switch self {
      case .disabled: .rule(rule)
      case .notFlightInstructor: .pilot(.instructorRatings)
      case .ignoresInstructionActivity: .pilot(.ignoresInstructionActivity)
      case .noInstrumentRating: .pilot(.instrumentRatings)
      case .studentPilot: .pilot(.certificate)
    }
  }
}

extension RegulationReport {
  /// The remedy for a rule that didn't run, or `nil` if it ran or the report doesn't cover it.
  func remedy(for rule: RegulationRule) -> RuleRemedy? {
    statuses[rule].flatMap { RuleRemedy(rule: rule, status: $0) }
  }
}

extension LogbookSession {
  /// Opens Logbook Settings on the page that lets a rule run, pointing out what to change.
  func showSettings(for remedy: RuleRemedy) {
    spotlitSettings = remedy.targets
    logbookSettingsPage = remedy.page
  }
}
