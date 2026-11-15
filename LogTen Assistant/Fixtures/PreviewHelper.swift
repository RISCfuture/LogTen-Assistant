import AuditWorkflow
import FlightSources
import Foundation
import LogbookModel
import LogbookStore
import PilotLookup
import SwiftUI
import Tracks

/// Sample data for SwiftUI previews, drawn from ``SampleLogbook``.
enum PreviewHelper {
  /// The sample logbook's records.
  static var sample: SampleLogbook {
    // swiftlint:disable:next force_unwrapping
    SampleLogbook(named: SampleLogbook.standardName)!
  }

  /// A flight from the sample logbook that has violations.
  static var flight: Flight {
    sample.logbook.flights[1]
  }

  /// A recent logbook in a made-up group container.
  static var recentReference: LogbookReference {
    let folder = URL(
      filePath: "/Users/pilot/Library/Group Containers/group.com.coradine.LogTenPro",
      directoryHint: .isDirectory
    )
    let logbook = LogbookLocation(directory: folder.appending(path: "LogTenProData_SAMPLE"))
    var reference = LogbookReference(logbook: logbook, in: folder, bookmark: Data())
    reference.displayName = String(localized: "Alex Aviator’s Logbook")
    return reference
  }

  /// FAA airmen matching a name search.
  static var airmen: [AirmanMatch] {
    var commercial = AirmanCertificates([])
    commercial.certificateLevel = .commercial
    commercial.categoryClassRatings = [.airplaneSingleEngineLand, .airplaneMultiEngineLand]
    commercial.instrumentRatings = [.airplane]
    commercial.typeRatings = ["SF50"]
    var student = AirmanCertificates([])
    student.certificateLevel = .student
    return [
      AirmanMatch(
        id: "A0000001",
        name: "ALEX AVIATOR",
        location: "PALO ALTO, CA",
        certificates: commercial
      ),
      AirmanMatch(
        id: "A0000002",
        name: "ALEX AVIATOR",
        location: "BOISE, ID",
        certificates: student
      )
    ]
  }

  /// A short track from Palo Alto toward Monterey, with its takeoff.
  static var track: FindingTrack {
    let start = Date(timeIntervalSince1970: 1_772_391_600)
    let samples = (0..<30).map { step in
      TrackSample(
        time: start.addingTimeInterval(Double(step) * 60),
        latitudeDeg: 37.461 - Double(step) * 0.029,
        longitudeDeg: -122.115 + Double(step) * 0.009,
        groundSpeedKts: 110
      )
    }
    let takeoff = TrackEvent(
      kind: .takeoff,
      time: start,
      latitudeDeg: samples[0].latitudeDeg,
      longitudeDeg: samples[0].longitudeDeg,
      confidence: .medium
    )
    return FindingTrack(samples: samples, events: [takeoff])
  }

  /// The first of three ADS-B archive days being downloaded.
  static var adsbDay: ADSBArchiveDay {
    // swiftlint:disable:next force_unwrapping
    ADSBArchiveDay(year: 2026, month: 11, day: 1)!
  }

  /// An ADS-B download partway through its first day.
  static var adsbProgress: DownloadProgress {
    DownloadProgress(
      day: adsbDay,
      dayIndex: 0,
      dayCount: 3,
      bytesRead: 1_200_000_000,
      totalBytes: 3_100_000_000,
      dayFraction: 0.39,
      tracesFound: 2
    )
  }

  /// An ADS-B download waiting to reconnect.
  static var adsbRetry: RetryWait {
    RetryWait(reason: .connectionLost, attempt: 3, resumesAt: .now.addingTimeInterval(8))
  }

  /// What an ADS-B download saved.
  static var adsbSummary: DownloadSummary {
    DownloadSummary(tracesSaved: 4, daysDownloaded: 3, daysWithoutTraces: [])
  }

  /// An ADS-B download that ran out of retries on its second day.
  static var adsbFailure: DownloadFailure {
    DownloadFailure(
      // swiftlint:disable:next force_unwrapping
      day: ADSBArchiveDay(year: 2026, month: 11, day: 2)!,
      error: ADSBTransferError.retriesExhausted(
        part: 2,
        partCount: 3,
        attempts: 9,
        reason: .connectionLost
      ),
      summary: DownloadSummary(tracesSaved: 2, daysDownloaded: 1, daysWithoutTraces: [])
    )
  }

  /**
   A library of recent logbooks kept in a defaults domain of its own, emptied first so the
   preview shows only the logbooks it passes.

   - Parameter recents: The logbooks to list, most recent first.
   */
  static func library(recents: [LogbookReference] = []) -> LogbookLibrary {
    let domain = "LogbookLibraryPreview"
    UserDefaults.standard.removePersistentDomain(forName: domain)
    let library = LogbookLibrary(defaults: UserDefaults(suiteName: domain) ?? .standard)
    recents.reversed().forEach(library.noteOpened)
    return library
  }

  /// A session for the sample logbook, not yet loaded.
  static func session() -> LogbookSession {
    LogbookSession(reference: SampleLogbook.reference)
  }

  /// The Audit & Fix table rows of a review queue's findings in a loaded session, or of every
  /// finding.
  static func findingRows(of queue: ReviewQueue? = nil, in session: LogbookSession) -> [FindingRow]
  {
    FindingRow.rows(
      for: queue.map { session.findings(in: FindingList(queue: $0)) } ?? session.auditRun?.findings
        ?? [],
      book: session.reviewBook,
      picked: session.pickedCorrections,
      customFields: session.logbook?.customFields ?? [],
      flight: session.flight
    )
  }

  /// The Violations table rows for a loaded session.
  static func violationRows(in session: LogbookSession) -> [ViolationRow] {
    guard let report = session.regulationReport else { return [] }
    return ViolationRow.rows(
      in: report,
      for: nil,
      flight: session.flight,
      matching: "",
      in: session.settings.pilot.homeTimeZone
    )
  }
}
