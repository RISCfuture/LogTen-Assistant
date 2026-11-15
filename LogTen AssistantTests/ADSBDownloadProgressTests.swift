import FlightSources
import Foundation
import Testing

@testable import LogTen_Assistant

@MainActor
struct ADSBDownloadProgressTests {
  private static let day = ADSBArchiveDay(year: 2026, month: 11, day: 5)!

  private static func progress(
    dayIndex: Int,
    dayCount: Int,
    bytesRead: Int64 = 0,
    totalBytes: Int64? = nil,
    dayFraction: Double = 0
  ) -> DownloadProgress {
    DownloadProgress(
      day: day,
      dayIndex: dayIndex,
      dayCount: dayCount,
      bytesRead: bytesRead,
      totalBytes: totalBytes,
      dayFraction: dayFraction,
      tracesFound: 0
    )
  }

  @Test
  func theFractionFollowsBytesWhenEveryDaysSizeIsKnownAndNeverPassesOne() {
    #expect(
      Self.progress(dayIndex: 1, dayCount: 4, bytesRead: 250, totalBytes: 1_000).fractionCompleted
        == 0.25
    )
    #expect(
      Self.progress(dayIndex: 3, dayCount: 4, bytesRead: 1_200, totalBytes: 1_000).fractionCompleted
        == 1
    )
  }

  @Test(
    "Without sizes the fraction counts finished days plus the current day's share",
    arguments: [
      (dayIndex: 0, dayCount: 4, dayFraction: 0.0, expected: 0.0),
      (dayIndex: 1, dayCount: 4, dayFraction: 0.5, expected: 0.375),
      (dayIndex: 0, dayCount: 0, dayFraction: 0.5, expected: 0.5)
    ]
  )
  func theFractionFallsBackToDays(
    dayIndex: Int,
    dayCount: Int,
    dayFraction: Double,
    expected: Double
  ) {
    let progress = Self.progress(dayIndex: dayIndex, dayCount: dayCount, dayFraction: dayFraction)
    #expect(progress.fractionCompleted == expected)
  }

  @Test
  func aFailureKeepsItsReasonOnlyWhenTheErrorGaveOne() {
    let summary = DownloadSummary(tracesSaved: 2, daysDownloaded: 1, daysWithoutTraces: [])
    let bare = DownloadFailure(
      day: Self.day,
      error: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"]),
      summary: summary
    )
    #expect(bare.message == "Offline")
    #expect(bare.reason == nil)

    let detailed = DownloadFailure(
      day: Self.day,
      error: NSError(
        domain: "Test",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "Offline",
          NSLocalizedFailureReasonErrorKey: "No route.",
          NSLocalizedRecoverySuggestionErrorKey: "Reconnect."
        ]
      ),
      summary: summary
    )
    #expect(detailed.reason == "No route. Reconnect.")
  }
}
