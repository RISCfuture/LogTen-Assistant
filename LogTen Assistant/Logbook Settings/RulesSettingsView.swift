import Audit
import LogbookModel
import Regulations
import SwiftUI

/// Logbook Settings ▸ Rules: which checks run, custom rules, places that aren't airports,
/// currency events confirmed outside the logbook, and tolerances.
struct RulesSettingsView: View {
  @Binding var rules: RuleSettings
  let customFields: [CustomFieldDefinition]

  /// Whether to expand the regulations, such as to point out one of them.
  var revealsRegulations = false

  var body: some View {
    Form {
      EnabledRulesSection(rules: $rules, revealsRegulations: revealsRegulations)
      CustomRulesSection(rules: $rules.customRules, customFields: customFields)
      ConfirmedEventsSection(events: $rules.confirmedCurrencyEvents)
      PlacesSection(nonAirportPlaces: $rules.nonAirportPlaces)
      TolerancesSection(tolerances: $rules.tolerances)
    }
    .formStyle(.grouped)
  }
}

/// Place identifiers that aren't airports.
private struct PlacesSection: View {
  @Binding var nonAirportPlaces: Set<String>

  @AppStorage("rulesSettings.placesExpanded")
  private var isExpanded = false

  var body: some View {
    Section("Places", isExpanded: $isExpanded) {
      TextField("Not Airports", text: text, prompt: Text("Private strip, Lake Tahoe"))
        .accessibilityIdentifier("rulesSettings.nonAirportPlaces")
      Text(
        "Place identifiers, separated by commas, that aren’t airports and shouldn’t be checked against FAA data."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var text: Binding<String> {
    Binding {
      nonAirportPlaces.sorted().joined(separator: ", ")
    } set: { text in
      nonAirportPlaces = Set(
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
          !$0.isEmpty
        }
      )
    }
  }
}

/// A toggle per rule: the regulations, the consistency checks grouped by category, and the
/// other audit rules.
private struct EnabledRulesSection: View {
  @Binding var rules: RuleSettings
  let revealsRegulations: Bool

  @AppStorage("rulesSettings.regulationsExpanded")
  private var regulationsExpanded = true
  @AppStorage("rulesSettings.otherRulesExpanded")
  private var otherRulesExpanded = false

  var body: some View {
    Section("Regulations", isExpanded: $regulationsExpanded) {
      ForEach(RegulationRule.allCases, id: \.self) { rule in
        Toggle(rule.title, isOn: $rules.binding(for: rule.id))
          .toggleStyle(.checkbox)
          .frame(maxWidth: .infinity, alignment: .leading)
          .spotlightTarget(.rule(rule))
      }
    }
    .onAppear { if revealsRegulations { regulationsExpanded = true } }
    ChecksSection(rules: $rules)
    Section("Other Audit Rules", isExpanded: $otherRulesExpanded) {
      ForEach(RuleDisplay.auditRules, id: \.self) { rule in
        Toggle(RuleDisplay.title(of: rule), isOn: $rules.binding(for: rule))
          .toggleStyle(.checkbox)
          .accessibilityIdentifier("rulesSettings.rule.\(rule.rawValue)")
      }
    }
  }
}

/// Every consistency check, grouped by category, each with what it looks for and a toggle.
private struct ChecksSection: View {
  @Binding var rules: RuleSettings

  @State private var expanded = Set<ConsistencyCategory>()
  @AppStorage("rulesSettings.checksExpanded")
  private var isSectionExpanded = true

  var body: some View {
    Section("Checks", isExpanded: $isSectionExpanded) {
      Text("Checks you turn off report nothing the next time the audit runs.")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(ConsistencyCategory.allCases, id: \.self) { category in
        CheckCategoryGroup(
          category: category,
          rules: $rules,
          isExpanded: Binding {
            expanded.contains(category)
          } set: { isExpanded in
            if isExpanded { expanded.insert(category) } else { expanded.remove(category) }
          }
        )
      }
    }
  }
}

/// One category of checks, collapsible, with how many of its checks are on.
private struct CheckCategoryGroup: View {
  let category: ConsistencyCategory
  @Binding var rules: RuleSettings
  @Binding var isExpanded: Bool

  private var checks: [ConsistencyRule] { category.rules.filter(\.isImplemented) }

  private var enabledCount: Int { checks.count { $0.isEnabled(in: rules) } }

  var body: some View {
    if !checks.isEmpty {
      DisclosureGroup(isExpanded: $isExpanded) {
        ForEach(checks, id: \.self) { rule in
          Toggle(isOn: $rules.binding(for: rule.id, byDefault: rule.isEnabledByDefault)) {
            Text(rule.title)
            Text(rule.summary)
          }
          .toggleStyle(.checkbox)
          .accessibilityIdentifier("rulesSettings.rule.\(rule.rawValue)")
        }
      } label: {
        LabeledContent(category.title) {
          Text("\(enabledCount, format: .number) of \(checks.count, format: .number) on")
        }
      }
      .accessibilityIdentifier("rulesSettings.category.\(category.rawValue)")
    }
  }
}

extension Binding<RuleSettings> {
  /// Whether a rule runs, as a binding for its toggle.
  fileprivate func binding(for rule: RuleID, byDefault: Bool = true) -> Binding<Bool> {
    Binding<Bool> {
      wrappedValue.isEnabled(rule, byDefault: byDefault)
    } set: { isOn in
      wrappedValue.setEnabled(isOn, rule, byDefault: byDefault)
    }
  }
}

/// The user's own consistency rules.
private struct CustomRulesSection: View {
  private static let builtInFields: [LogTenFieldKey] = [
    .flightTotalTime, .flightPIC, .flightSIC, .flightNight, .flightCrossCountry,
    .flightActualInstrument, .flightSimulatedInstrument, .flightDualGiven, .flightDualReceived,
    .flightSolo, .flightDayTakeoffs, .flightNightTakeoffs, .flightDayLandings,
    .flightNightLandings, .flightFullStops, .flightHolds
  ]

  @Binding var rules: [CustomRule]
  let customFields: [CustomFieldDefinition]

  private var fields: [LogTenFieldKey] {
    Self.builtInFields + customFields.map(\.key).filter { $0.entity == .flight }
  }

  var body: some View {
    Section {
      ForEach($rules) { $rule in
        CustomRuleRow(rule: $rule, fields: fields, customFields: customFields) {
          rules.removeAll { $0.id == rule.id }
        }
      }
      Button("Add Rule") {
        rules.append(
          CustomRule(
            id: RuleID(rawValue: "rule-\(UUID().uuidString.prefix(8).lowercased())"),
            kind: .subset,
            field: .flightNight,
            other: .flightTotalTime
          )
        )
      }
      .accessibilityIdentifier("rulesSettings.addRule")
    } header: {
      Text("Custom Rules")
    }
  }
}

/// One custom rule.
private struct CustomRuleRow: View {
  @Binding var rule: CustomRule
  let fields: [LogTenFieldKey]
  let customFields: [CustomFieldDefinition]
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Picker("Field", selection: $rule.field) {
          FieldOptions(fields: fields, customFields: customFields)
        }
        Button("Remove", systemImage: "minus.circle", role: .destructive, action: remove)
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .accessibilityIdentifier("rulesSettings.removeRule.\(rule.id.rawValue)")
      }
      HStack {
        Text("Must")
        Picker("Must", selection: $rule.kind) {
          ForEach(CustomRule.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        if rule.kind != .nonnegative {
          Picker("Than", selection: otherField) {
            FieldOptions(fields: fields, customFields: customFields)
          }
          .labelsHidden()
        }
        Spacer()
        Picker("Severity", selection: $rule.severity) {
          ForEach(Severity.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .fixedSize()
      }
    }
  }

  private var otherField: Binding<LogTenFieldKey> {
    Binding {
      rule.other ?? .flightTotalTime
    } set: {
      rule.other = $0
    }
  }
}

/// The fields a custom rule can check, as picker options.
private struct FieldOptions: View {
  let fields: [LogTenFieldKey]
  let customFields: [CustomFieldDefinition]

  var body: some View {
    ForEach(fields, id: \.self) { field in
      Text(LogbookFormat.fieldTitle(field, customFields: customFields)).tag(field)
    }
  }
}

/// Currency events the pilot confirms outside the logbook.
private struct ConfirmedEventsSection: View {
  private static let categories: [AircraftCategory] = [
    .airplane, .rotorcraft, .poweredLift, .glider, .lighterThanAir
  ]

  @Binding var events: [ConfirmedCurrencyEvent]

  @AppStorage("rulesSettings.confirmedEventsExpanded")
  private var isExpanded = false

  var body: some View {
    Section("Confirmed Currency Events", isExpanded: $isExpanded) {
      ForEach(events.indices, id: \.self) { index in
        HStack {
          DatePicker("Date", selection: date(of: index), displayedComponents: .date)
            .labelsHidden()
          Picker("Event", selection: $events[index].kind) {
            ForEach(ConfirmedCurrencyEvent.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          Picker("Category", selection: $events[index].category) {
            Text("Any").tag(AircraftCategory?.none)
            ForEach(Self.categories, id: \.self) { Text($0.title).tag(Optional($0)) }
          }
          .labelsHidden()
          Button("Remove", systemImage: "minus.circle", role: .destructive) {
            events.remove(at: index)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
      }
      Button("Add Event") {
        events.append(
          ConfirmedCurrencyEvent(
            date: Calendar.current.dateComponents([.year, .month, .day], from: .now),
            kind: .flightReview
          )
        )
      }
      Text("Events the logbook doesn’t show, such as a flight review logged elsewhere.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func date(of index: Int) -> Binding<Date> {
    Binding {
      Calendar.current.date(from: events[index].date) ?? .now
    } set: { date in
      events[index].date = Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
  }
}

/// How far values may differ and still agree.
private struct TolerancesSection: View {
  @Binding var tolerances: AuditTolerances

  var body: some View {
    Section("Tolerances") {
      Stepper(value: $tolerances.timeToleranceMinutes, in: 1...60) {
        LabeledContent("Times Agree Within", value: minutes(tolerances.timeToleranceMinutes))
      }
      Stepper(value: $tolerances.duplicateTimeMinutes, in: 1...60) {
        LabeledContent("Duplicates Within", value: minutes(tolerances.duplicateTimeMinutes))
      }
      Stepper(value: $tolerances.maximumFlightMinutes, in: 60...(48 * 60), step: 60) {
        LabeledContent(
          "Longest Plausible Flight",
          value: LogbookFormat.duration(minutes: tolerances.maximumFlightMinutes)
        )
      }
    }
  }

  private func minutes(_ value: UInt) -> String {
    Measurement(value: Double(value), unit: UnitDuration.minutes)
      .formatted(.measurement(width: .abbreviated))
  }
}

nonisolated extension CustomRule.Kind {
  var title: String {
    switch self {
      case .subset: String(localized: "not exceed")
      case .nonnegative: String(localized: "not be negative")
      case .requires: String(localized: "require")
    }
  }
}

nonisolated extension ConfirmedCurrencyEvent.Kind {
  var title: String {
    switch self {
      case .flightReview: String(localized: "Flight Review")
      case .instrumentProficiencyCheck: String(localized: "Instrument Proficiency Check")
      case .instrumentRating: String(localized: "Instrument Rating")
      case .proficiencyCheck: String(localized: "61.58 Proficiency Check")
    }
  }
}

nonisolated extension AircraftCategory {
  var title: String {
    switch self {
      case .airplane: String(localized: "Airplane")
      case .rotorcraft: String(localized: "Rotorcraft")
      case .poweredLift: String(localized: "Powered Lift")
      case .glider: String(localized: "Glider")
      case .lighterThanAir: String(localized: "Lighter-than-Air")
      default: rawValue.replacing("_", with: " ").capitalized
    }
  }
}

#Preview("In Logbook Settings", traits: .sampleSession { $0.logbookSettingsPage = .rules }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}

#Preview(
  "Regulation Pointed Out",
  traits: .sampleSession { session in
    session.spotlitSettings = [.rule(.noNVGCurrency)]
    session.logbookSettingsPage = .rules
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}
