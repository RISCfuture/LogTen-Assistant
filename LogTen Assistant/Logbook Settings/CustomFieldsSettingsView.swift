import LogbookModel
import Regulations
import SwiftUI

/// Logbook Settings ▸ Custom Fields: which of the logbook's fields holds each value the checks
/// need. Checks whose fields are unmapped don't run.
struct CustomFieldsSettingsView: View {
  @Binding var mapping: FieldMapping
  let customFields: [CustomFieldDefinition]

  private var flightRoles: [FieldRole] { FieldRole.allCases.filter { $0.entity == .flight } }
  private var aircraftTypeRoles: [FieldRole] {
    FieldRole.allCases.filter { $0.entity == .aircraftType }
  }

  var body: some View {
    Form {
      Section {
        ForEach(flightRoles, id: \.self) { role in
          FieldRolePicker(role: role, mapping: $mapping, customFields: customFields)
            .spotlightTarget(.fieldRole(role))
        }
      } header: {
        Text("Flight Fields")
      } footer: {
        Text("Fields are matched to the titles you gave them in LogTen.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Aircraft Type Fields") {
        ForEach(aircraftTypeRoles, id: \.self) { role in
          FieldRolePicker(role: role, mapping: $mapping, customFields: customFields)
            .spotlightTarget(.fieldRole(role))
        }
      }
      Section {
        Button("Suggest from Field Titles", action: suggestUnmappedRoles)
          .accessibilityIdentifier("customFields.suggest")
      }
    }
    .formStyle(.grouped)
  }

  /// Maps each unmapped role whose conventional title matches exactly one field.
  private func suggestUnmappedRoles() {
    let suggestion = FieldMapping.suggested(for: customFields)
    for role in mapping.unmappedRoles {
      try? mapping.assign(suggestion[role], to: role)
    }
  }
}

/// Chooses the field that holds one role.
private struct FieldRolePicker: View {
  let role: FieldRole
  @Binding var mapping: FieldMapping
  let customFields: [CustomFieldDefinition]

  private var candidates: [FieldOption] {
    let custom = customFields.filter { role.accepts($0.key) }
      .map { FieldOption(key: $0.key, title: $0.title) }
    let builtIn = [role.defaultKey, mapping[role]].compactMap(\.self)
      .filter { $0.customSlot == nil }
      .map { FieldOption(key: $0, title: String(localized: "LogTen \(role.title)")) }
    var seen = Set<LogTenFieldKey>()
    return (builtIn + custom).filter { seen.insert($0.key).inserted }
  }

  private var selection: Binding<LogTenFieldKey?> {
    Binding {
      mapping[role]
    } set: { key in
      try? mapping.assign(key, to: role)
    }
  }

  private var dependentRulesNote: String? {
    let rules = role.dependentRules
    guard !rules.isEmpty else { return nil }
    let titles = rules.map(\.title).formatted(.list(type: .and))
    return mapping[role] == nil
      ? String(localized: "Until this is mapped, these rules aren’t checked: \(titles).")
      : String(localized: "Used by \(titles).")
  }

  var body: some View {
    Picker(selection: selection) {
      Text("Not Mapped").tag(LogTenFieldKey?.none)
      ForEach(candidates, id: \.key) { option in
        Text(option.title).tag(LogTenFieldKey?.some(option.key))
      }
    } label: {
      Text(role.title)
      Text(role.summary)
      if let dependentRulesNote {
        Text(dependentRulesNote)
      }
    }
    .accessibilityIdentifier("customFields.role.\(role.rawValue)")
  }
}

/// A field a role can be mapped to.
private struct FieldOption {
  let key: LogTenFieldKey
  let title: String
}

#Preview("In Logbook Settings", traits: .sampleSession { $0.logbookSettingsPage = .customFields }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}

#Preview(
  "Fields to Map",
  traits: .sampleSession { session in
    session.spotlitSettings = [.fieldRole(.nightVisionGoggleProficiencyCheck)]
    session.logbookSettingsPage = .customFields
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}
