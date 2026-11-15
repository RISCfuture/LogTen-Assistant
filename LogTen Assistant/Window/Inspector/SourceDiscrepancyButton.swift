import SwiftUI

/// A red exclamation mark beside a detail the flight's sources disagree with, which shows what
/// each source recorded in a popover.
struct SourceDiscrepancyButton: View {
  let discrepancy: SourceDiscrepancy

  @State private var isShowingReadings = false

  var body: some View {
    Button {
      isShowingReadings.toggle()
    } label: {
      Label("Compare Sources", systemImage: "exclamationmark.circle.fill")
        .labelStyle(.iconOnly)
        .foregroundStyle(.red)
    }
    .buttonStyle(.borderless)
    .help("The flight’s sources disagree with the logbook")
    .popover(isPresented: $isShowingReadings) {
      SourceReadings(discrepancy: discrepancy)
    }
  }
}

/// What the logbook and each source recorded for a value, one source to a row, with the source
/// the audit preferred and any source whose own records conflict.
struct SourceReadings: View {
  let discrepancy: SourceDiscrepancy

  private var conflictingSources: [String] {
    discrepancy.readings.filter(\.hasConflict).map(\.source)
  }

  var body: some View {
    VStack(alignment: .leading) {
      Grid(alignment: .leadingFirstTextBaseline) {
        GridRow {
          Text("Logbook").foregroundStyle(.secondary)
          Text(discrepancy.logbookValue).monospacedDigit()
        }
        Divider()
        ForEach(discrepancy.readings, id: \.self) { reading in
          SourceReadingRow(reading: reading)
        }
      }
      ForEach(conflictingSources, id: \.self) { source in
        Text("\(source)’s records disagree with each other.")
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .textSelection(.enabled)
    .inspectorTextSize()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(discrepancy.title)
    .accessibilityIdentifier("sourceReadings")
  }
}

/// One source's name and value, the value followed by whether the audit preferred it or
/// couldn't use it.
private struct SourceReadingRow: View {
  let reading: SourceDiscrepancy.Reading

  var body: some View {
    GridRow {
      Text(reading.source).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline) {
        Text(reading.value)
          .monospacedDigit()
          .foregroundStyle(reading.isUsable ? .primary : .secondary)
        ReadingNote(reading: reading)
      }
    }
  }
}

/// Notes that the audit preferred a source's value, or couldn't use it.
private struct ReadingNote: View {
  let reading: SourceDiscrepancy.Reading

  var body: some View {
    if reading.isPreferred {
      Label("Preferred", systemImage: "star.fill")
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
        .help("The audit compared this source’s value with the logbook’s")
    } else if !reading.isUsable {
      Text("Unusable")
        .foregroundStyle(.secondary)
        .help("The audit couldn’t use this source’s value")
    }
  }
}

#Preview("Readings Popover") {
  PopoverPreview {
    if let discrepancy = PreviewHelper.discrepancies(of: PreviewHelper.flight).first {
      SourceReadings(discrepancy: discrepancy)
    }
  }
}

#Preview("Count Readings Popover") {
  PopoverPreview {
    if let discrepancy = PreviewHelper.discrepancies(of: PreviewHelper.flight).last {
      SourceReadings(discrepancy: discrepancy)
    }
  }
}
