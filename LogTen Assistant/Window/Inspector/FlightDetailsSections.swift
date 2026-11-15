import LogbookModel
import SwiftUI

/// A flight's details in LogTen's inspector sections, each a column of labeled, boxed values,
/// with a marker beside any value the flight's sources disagree with.
struct FlightDetailsSections: View {
  let details: FlightDetails

  var body: some View {
    ForEach(details.sections) { section in
      InspectorSection(section.kind.title) {
        DetailGrid(items: section.items)
      }
    }
  }
}

/// Labels aligned to their trailing edge beside the boxed values, as in LogTen's inspector. A
/// minimum label width keeps most sections' boxes in line with each other; an unlabeled value,
/// such as a passenger, spans the full width.
private struct DetailGrid: View {
  private static let horizontalSpacing = 8.0
  private static let verticalSpacing = 4.0

  let items: [FlightDetails.Item]

  @ScaledMetric private var labelWidth = 84.0

  var body: some View {
    Grid(
      alignment: .leadingFirstTextBaseline,
      horizontalSpacing: Self.horizontalSpacing,
      verticalSpacing: Self.verticalSpacing
    ) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        GridRow {
          if item.label.isEmpty {
            DetailRowValues(item: item)
              .gridCellColumns(2)
          } else {
            Text(item.label)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
              .frame(minWidth: labelWidth, alignment: .trailing)
              .gridColumnAlignment(.trailing)
              .accessibilityHidden(true)
            DetailRowValues(item: item)
          }
        }
      }
    }
  }
}

/// A detail's boxes, followed by a marker when the flight's sources disagree with it.
private struct DetailRowValues: View {
  let item: FlightDetails.Item

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      DetailValues(item: item)
      if let discrepancy = item.discrepancy {
        SourceDiscrepancyButton(discrepancy: discrepancy)
          .accessibilityIdentifier(
            item.field.map { "flightDetails.\($0.rawValue).discrepancy" } ?? ""
          )
      }
    }
  }
}

/// A detail's boxes, side by side: one for most details, UTC and local for a time.
private struct DetailValues: View {
  let item: FlightDetails.Item

  private var accessibilityValue: String {
    let current = item.value.map(\.text).joined(separator: ", ")
    guard item.isChanged else { return current }
    let proposed = item.proposedValue.map(\.text).joined(separator: ", ")
    let none = String(localized: "none")
    return String(
      localized:
        "\(current.isEmpty ? none : current), changes to \(proposed.isEmpty ? none : proposed)"
    )
  }

  var body: some View {
    HStack {
      ForEach(0..<item.partCount, id: \.self) { part in
        DetailValueBox(
          value: item.value.indices.contains(part) ? item.value[part] : nil,
          proposedValue: item.proposedValue.indices.contains(part)
            ? item.proposedValue[part] : nil
        )
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.label)
    .accessibilityValue(accessibilityValue)
    .accessibilityIdentifier(item.field.map { "flightDetails.\($0.rawValue)" } ?? "")
  }
}

/// One boxed value, drawn as “old → new” with an accent outline when a correction changes it.
/// An unset value shows a blank box that still has a text baseline for its label to align to.
private struct DetailValueBox: View {
  private static let cornerRadius = 4.0
  private static let horizontalPadding = 6.0
  private static let verticalPadding = 2.0

  let value: FlightDetails.Value?
  let proposedValue: FlightDetails.Value?

  private var isChanged: Bool { value != proposedValue }

  private var outline: AnyShapeStyle {
    isChanged ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      if isChanged {
        ChangedValueText(value: value?.text, proposedValue: proposedValue?.text)
      } else {
        Text(value?.text ?? " ")
      }
      Spacer(minLength: 0)
      if let qualifier = (proposedValue ?? value)?.qualifier {
        Text(qualifier).foregroundStyle(.secondary)
      }
    }
    .monospacedDigit()
    .padding(.horizontal, Self.horizontalPadding)
    .padding(.vertical, Self.verticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: .rect(cornerRadius: Self.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(outline)
    }
  }
}

/// A value a correction changes, as the old value struck through and the new one emphasized.
private struct ChangedValueText: View {
  let value: String?
  let proposedValue: String?

  var body: some View {
    let none = String(localized: "—")
    let old = Text(value ?? none).strikethrough(value != nil).foregroundStyle(.secondary)
    let new = Text(proposedValue ?? none).fontWeight(.semibold)
    Text("\(old) → \(new)")
  }
}

#Preview("Flight") {
  InspectorColumnPreview {
    InspectorPage {
      FlightDetailsSections(
        details: FlightDetails(
          flight: PreviewHelper.flight,
          customFields: PreviewHelper.sample.logbook.customFields,
          timeZone: PreviewHelper.sample.settings.pilot.homeTimeZone
        )
      )
    }
  }
}

#Preview("Proposed Correction") {
  InspectorColumnPreview {
    InspectorPage {
      FlightDetailsSections(
        details: FlightDetails(
          flight: PreviewHelper.flight,
          customFields: PreviewHelper.sample.logbook.customFields,
          timeZone: PreviewHelper.sample.settings.pilot.homeTimeZone,
          changes: PreviewHelper.correction(of: PreviewHelper.flight).changes
        )
      )
    }
  }
}

#Preview("Sources Disagree") {
  InspectorColumnPreview {
    InspectorPage {
      FlightDetailsSections(
        details: FlightDetails(
          flight: PreviewHelper.flight,
          customFields: PreviewHelper.sample.logbook.customFields,
          timeZone: PreviewHelper.sample.settings.pilot.homeTimeZone,
          discrepancies: PreviewHelper.discrepancies(of: PreviewHelper.flight)
        )
      )
    }
  }
}
