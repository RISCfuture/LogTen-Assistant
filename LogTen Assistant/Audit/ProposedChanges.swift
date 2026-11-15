import LogbookModel
import SwiftUI

/// A correction's changes as “old → new”, each value copyable.
struct ProposedChanges: View {
  let changes: [FieldChange]
  let customFields: [CustomFieldDefinition]

  var body: some View {
    ForEach(changes, id: \.self) { change in
      LabeledContent(LogbookFormat.fieldTitle(change.field, customFields: customFields)) {
        Text(
          "\(LogbookFormat.auditValue(change.old, of: change.field)) → \(LogbookFormat.auditValue(change.new, of: change.field))"
        )
        .monospacedDigit()
        .textSelection(.enabled)
      }
      .accessibilityIdentifier("proposedChange.\(change.field.rawValue)")
    }
  }
}

#Preview("In the Inspector") {
  InspectorColumnPreview {
    InspectorPage {
      InspectorSection("Changes") {
        ProposedChanges(
          changes: PreviewHelper.correction(of: PreviewHelper.flight).changes,
          customFields: []
        )
      }
    }
  }
}
