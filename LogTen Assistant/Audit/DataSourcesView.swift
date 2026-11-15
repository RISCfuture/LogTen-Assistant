import AuditWorkflow
import FlightSources
import LogbookModel
import SwiftUI

/// Audit & Fix ▸ Data Sources: the running task or the last one's result at the top, then
/// where the evidence comes from, how fresh it is, and how much of each aircraft's flying it
/// covers, on one scrolling page.
///
/// The page is a scroll view holding the coverage table and a grouped form that doesn't scroll
/// by itself. The table sits outside the form because a table inside a form row never receives
/// the scroll wheel; outside it, the table scrolls its own rows under the pointer and the page
/// scrolls everywhere else.
struct DataSourcesView: View {
  let session: LogbookSession

  /// The widest the page's content grows, so labels stay close to their values and buttons in a
  /// wide content column.
  @ScaledMetric private var contentMaxWidth = 640.0

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if session.activity != nil || session.dataSourceStatus != nil {
          Form {
            StatusSection(session: session)
          }
          .formStyle(.grouped)
          .scrollDisabled(true)
          .fixedSize(horizontal: false, vertical: true)
        }
        CoverageSection(session: session)
        Form {
          FlyStoSection(session: session)
          ADSBSection(session: session)
          ReferenceDataSection(session: session)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: contentMaxWidth)
      .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("dataSources")
  }
}

/// The running task, or the last task's result, shown only while there is one.
private struct StatusSection: View {
  let session: LogbookSession

  var body: some View {
    if let activity = session.activity {
      Section {
        HStack {
          ActivityRow(activity: activity)
          if session.dataTask != nil {
            Button("Stop") { session.stopDataTask() }
              .accessibilityIdentifier("dataSources.stop")
          }
        }
      }
    } else if let status = session.dataSourceStatus {
      Section {
        Text(status)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("dataSources.status")
      }
    }
  }
}

/// A running data-source task.
private struct ActivityRow: View {
  let activity: Activity

  var body: some View {
    if let progress = activity.progress {
      ProgressView(activity.title, value: progress.fractionCompleted)
    } else {
      ProgressView(activity.title).progressViewStyle(.linear)
    }
  }
}

/// FlySto's account, records, sync state and commands.
private struct FlyStoSection: View {
  let session: LogbookSession

  var body: some View {
    Section {
      if !session.hasFlyStoToken {
        FlyStoAccountRow()
      }
      LabeledContent("Records") { Text(session.flyStoRecordCount, format: .number) }
        .accessibilityIdentifier("dataSources.flyStoRecords")
      LabeledContent("Last Synced") {
        HStack {
          Text(dateText(session.flyStoState.lastSyncedAt))
          Button("Sync Now") { Task { await session.syncFlySto() } }
            .disabled(!session.canStartDataTask)
            .accessibilityIdentifier("dataSources.syncFlySto")
        }
      }
      LabeledContent("Last Imported") {
        HStack {
          Text(dateText(session.flyStoState.lastImportedAt))
          Button("Import…") {
            let files = FilePanels.chooseFlyStoExports()
            Task { await session.importFlyStoExport(files) }
          }
          .disabled(!session.canStartDataTask)
          .accessibilityIdentifier("dataSources.importFlySto")
        }
      }
      LabeledContent("Data Logs") {
        Button("Upload…") { session.presentedSheet = .uploadLogs }
          .disabled(!session.canStartDataTask)
          .accessibilityIdentifier("dataSources.uploadLogs")
      }
    } header: {
      Text("FlySto")
    } footer: {
      Text(
        "FlySto parses the aircraft’s data logs. Sync fetches logs added since the last sync; you can also drop a CSV export and its web archive on the window."
      )
    }
  }

  private func dateText(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Never")
  }
}

/// Says FlySto has no API token and opens Settings on the Accounts pane.
private struct FlyStoAccountRow: View {
  @AppStorage(SettingsTab.storageKey)
  private var settingsTab = SettingsTab.accounts
  @Environment(\.openSettings)
  private var openSettings

  var body: some View {
    LabeledContent("Account") {
      HStack {
        Text("Not set up")
        Button("Set Up…") {
          settingsTab = .accounts
          openSettings()
        }
        .accessibilityIdentifier("dataSources.setUpFlySto")
      }
    }
    .accessibilityIdentifier("dataSources.flyStoAccount")
  }
}

/// The ADS-B traces downloaded for the logbook's aircraft, and the download running or the
/// last one's result.
private struct ADSBSection: View {
  let session: LogbookSession

  private var days: Int { Set(session.adsbTraces.map(\.day)).count }

  var body: some View {
    Section {
      ADSBDownloadRow(job: session.adsbDownload)
      LabeledContent("Traces") { Text(session.adsbTraces.count, format: .number) }
      LabeledContent("Days Covered") {
        HStack {
          Text(days, format: .number)
          Button("Fetch…") { session.presentedSheet = .fetchADSB }
            .disabled(!session.canFetchADSB)
            .accessibilityIdentifier("dataSources.fetchADSB")
        }
      }
    } header: {
      Text("ADS-B")
    } footer: {
      Text("Traces come from the adsb.lol archive, under the Open Database License (ODbL).")
    }
  }
}

/// FAA airport and approach data.
private struct ReferenceDataSection: View {
  let session: LogbookSession

  var body: some View {
    Section("Airport Data") {
      LabeledContent("NASR Cycle") {
        HStack {
          if let cycle = session.airportCycle {
            Text(cycle, format: LogbookFormat.cycleDate)
              .environment(\.timeZone, .gmt)
          } else {
            Text("Not downloaded")
          }
          Button("Update") { Task { await session.updateNASR() } }
            .disabled(!session.canStartDataTask)
            .accessibilityIdentifier("dataSources.updateNASR")
        }
      }
      LabeledContent("CIFP Cycle") {
        HStack {
          if let cycle = session.approachCycle {
            Text(cycle, format: LogbookFormat.cycleDate)
              .environment(\.timeZone, .gmt)
          } else {
            Text(session.hasApproachData ? "Added by hand" : "Not downloaded")
          }
          Button("Update") { Task { await session.updateApproachData() } }
            .disabled(!session.canStartDataTask)
            .accessibilityIdentifier("dataSources.updateCIFP")
        }
      }
    }
  }
}

/// How much of each aircraft's flying the evidence covers, laid out like the grouped form's
/// sections below it.
private struct CoverageSection: View {
  /// The grouped form's margin around its sections.
  private static let formInset = 20.0
  /// How far the grouped form indents a section's header from its rows' edge.
  private static let headerInset = 10.0

  let session: LogbookSession

  private var coverage: [AircraftCoverage] {
    guard let logbook = session.logbook else { return [] }
    return session.auditRun?.coverage(of: logbook) ?? []
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Coverage")
        .font(.headline)
        .padding(.leading, Self.headerInset)
        .accessibilityAddTraits(.isHeader)
      if coverage.isEmpty {
        Text("No aircraft flown.")
          .foregroundStyle(.secondary)
          .padding(.leading, Self.headerInset)
      } else {
        CoverageTable(coverage: coverage, timeZone: session.settings.pilot.homeTimeZone)
      }
    }
    .padding([.horizontal, .top], Self.formInset)
  }
}

/// Each aircraft's coverage in a sortable table of fixed height that scrolls its own rows, so a
/// logbook with many aircraft doesn't push the sources below it down the page.
private struct CoverageTable: View {
  private static let cornerRadius = 8.0

  let coverage: [AircraftCoverage]
  let timeZone: TimeZone

  @ScaledMetric private var height = 200.0
  @State private var sortOrder = [KeyPathComparator(\AircraftCoverage.flightCount, order: .reverse)]

  private var rows: [AircraftCoverage] { coverage.sorted(using: sortOrder) }

  var body: some View {
    Table(rows, sortOrder: $sortOrder) {
      TableColumn("Aircraft", value: \.registration)
        .width(min: 64, ideal: 72)
      TableColumn("Flights", value: \.flightCount) { aircraft in
        Text(aircraft.flightCount, format: .number).monospacedDigit()
      }
      .width(min: 48, ideal: 56)
      .alignment(.trailing)
      TableColumn("FlySto", value: \.flyStoCount) { aircraft in
        Text(aircraft.flyStoCount, format: .number).monospacedDigit()
      }
      .width(min: 48, ideal: 56)
      .alignment(.trailing)
      TableColumn("ADS-B", value: \.adsbCount) { aircraft in
        Text(aircraft.adsbCount, format: .number).monospacedDigit()
      }
      .width(min: 48, ideal: 56)
      .alignment(.trailing)
      TableColumn("Flown") { aircraft in
        CoverageDates(coverage: aircraft, timeZone: timeZone)
      }
      .width(min: 180, ideal: 200)
    }
    .tableStyle(.inset)
    .alternatingRowBackgrounds(.disabled)
    .scrollContentBackground(.hidden)
    .frame(height: height)
    .background(.fill.quaternary, in: .rect(cornerRadius: Self.cornerRadius))
    .clipShape(.rect(cornerRadius: Self.cornerRadius))
    .accessibilityIdentifier("dataSources.coverage")
  }
}

/// The span of an aircraft's entries.
private struct CoverageDates: View {
  let coverage: AircraftCoverage
  let timeZone: TimeZone

  var body: some View {
    if let first = coverage.firstFlight, let last = coverage.lastFlight {
      Text("\(LogbookFormat.date(first, in: timeZone)) – \(LogbookFormat.date(last, in: timeZone))")
        .foregroundStyle(.secondary)
    }
  }
}

#Preview("Idle", traits: .sampleSession { $0.sidebarSelection = .audit(.dataSources) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "Syncing, No FlySto Account",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.dataSources)
    session.hasFlyStoToken = false
    session.activity = Activity(title: String(localized: "Syncing FlySto…"))
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}

#Preview(
  "After a Sync",
  traits: .sampleSession { session in
    session.sidebarSelection = .audit(.dataSources)
    session.hasFlyStoToken = true
    session.dataSourceStatus = String(localized: "Synced 3 FlySto logs.")
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  PageColumnPreview(session: session)
}
