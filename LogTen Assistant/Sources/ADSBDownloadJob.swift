import FlightSources
import Foundation
import LogbookModel
import Observation

/**
 Downloads adsb.lol archives in the background for a logbook session, one day at a time, and
 saves each day's traces as soon as that day is done.

 The job belongs to the session rather than the sheet that starts it, so it keeps going while
 the user works elsewhere. While it runs it holds a user-initiated process activity, so App Nap
 and idle sleep don't stall the transfer. Stopping or failing keeps the days already finished;
 ``retry()`` carries on from the first day that isn't.
 */
@MainActor
@Observable
final class ADSBDownloadJob {
  private static let activityOptions: ProcessInfo.ActivityOptions = [
    .userInitiated, .idleSystemSleepDisabled
  ]
  private static let percentScale = 100.0

  /// Where the job stands.
  private(set) var state = State.idle {
    didSet { summarizeState() }
  }

  /// Whether the job is downloading or waiting to retry. Changes less often than ``state``, so
  /// menus and toolbars can observe it cheaply.
  private(set) var isActive = false

  /// How far the running job has come, in whole percent, or `nil` when it isn't running.
  private(set) var percentComplete: Int?

  /// Called when a run ends having saved traces, so the session can audit them.
  @ObservationIgnored var tracesDidSave: (() async -> Void)?

  @ObservationIgnored private let download: ADSBDayDownload
  @ObservationIgnored private var plan: Plan?
  @ObservationIgnored private var tally = Tally()
  @ObservationIgnored private var task: Task<Void, Never>?

  /// Whether a stopped or failed run has days left to download.
  var canResume: Bool {
    guard !isActive, let plan else { return false }
    return tally.completedDays < plan.days.count
  }

  /// The window subtitle while the job runs, such as “Downloading ADS-B… 38%”.
  var subtitle: String? {
    percentComplete.map {
      String(
        localized:
          "Downloading ADS-B… \(Double($0) / Self.percentScale, format: .percent.precision(.fractionLength(0)))"
      )
    }
  }

  /// Creates a job that downloads through a client and saves into a cache.
  init(client: ADSBLolClient, cache: ADSBTraceCache) {
    download = ADSBDayDownload(client: client, cache: cache)
  }

  /// How far through its release an update is: by bytes if the size is known, otherwise by
  /// the parts finished.
  private static func fraction(of update: ADSBFetchProgress) -> Double {
    if let total = update.totalBytes, total > 0 {
      return min(1, Double(update.bytesRead) / Double(total))
    }
    return Double(max(0, update.part - 1)) / Double(max(1, update.partCount))
  }

  /// Downloads the days of an estimate, keeping the traces of some aircraft.
  func start(_ estimate: ADSBEstimate, addresses: Set<ICAOAddress>) {
    guard !isActive, !estimate.days.isEmpty else { return }
    plan = Plan(days: estimate.days, addresses: addresses)
    tally = Tally()
    run()
  }

  /// Carries on from the first day not yet downloaded.
  func retry() {
    guard canResume else { return }
    run()
  }

  /// Stops the download. The days already finished stay saved.
  func stop() { task?.cancel() }

  /// Clears the result of a run that ended.
  func dismiss() {
    guard !isActive else { return }
    state = .idle
  }

  private func summarizeState() {
    let progress = state.progress
    if isActive != (progress != nil) { isActive = progress != nil }
    let percent = progress.map { Int(($0.fractionCompleted * Self.percentScale).rounded(.down)) }
    if percentComplete != percent { percentComplete = percent }
  }

  private func run() {
    guard let plan else { return }
    state = .preparing(progress(in: plan, dayIndex: tally.completedDays))
    let savedBefore = tally.saved
    task = Task {
      let activity = ProcessInfo.processInfo.beginActivity(
        options: Self.activityOptions,
        reason: String(localized: "Downloading ADS-B archives")
      )
      let outcome = await downloadRemainingDays(of: plan)
      ProcessInfo.processInfo.endActivity(activity)
      state = outcome
      task = nil
      if tally.saved > savedBefore { await tracesDidSave?() }
    }
  }

  private func downloadRemainingDays(of plan: Plan) async -> State {
    for index in plan.days.indices.dropFirst(tally.completedDays) {
      let day = plan.days[index]
      tally.currentDayBytes = 0
      do {
        let result = try await withProgress(dayIndex: index, of: plan) { report in
          try await download.fetch(day, for: plan.addresses, progress: report)
        }
        tally.record(result, of: day)
      } catch {
        if Task.isCancelled || error is CancellationError { return .stopped(tally.summary) }
        return .failed(DownloadFailure(day: day.release.day, error: error, summary: tally.summary))
      }
    }
    return .finished(tally.summary)
  }

  /// Runs a day's download, showing its progress reports in order as they arrive.
  private func withProgress<Result>(
    dayIndex: Int,
    of plan: Plan,
    _ body: (@escaping @Sendable (ADSBFetchProgress) -> Void) async throws -> Result
  ) async throws -> Result {
    let (updates, continuation) = AsyncStream.makeStream(
      of: ADSBFetchProgress.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    let watcher = Task {
      for await update in updates { show(update, dayIndex: dayIndex, of: plan) }
    }
    do {
      let result = try await body { continuation.yield($0) }
      continuation.finish()
      await watcher.value
      return result
    } catch {
      continuation.finish()
      await watcher.value
      throw error
    }
  }

  private func show(_ update: ADSBFetchProgress, dayIndex: Int, of plan: Plan) {
    guard isActive else { return }
    var progress = progress(in: plan, dayIndex: dayIndex)
    progress.bytesRead += update.bytesRead
    progress.dayFraction = Self.fraction(of: update)
    progress.tracesFound += update.found
    tally.currentDayBytes = update.bytesRead
    if let retry = update.retry {
      state = .retrying(
        progress,
        RetryWait(
          reason: retry.reason,
          attempt: retry.attempt,
          resumesAt: .now.addingTimeInterval(retry.delay / .seconds(1))
        )
      )
    } else {
      state = .downloading(progress)
    }
  }

  private func progress(in plan: Plan, dayIndex: Int) -> DownloadProgress {
    DownloadProgress(
      day: plan.days[min(dayIndex, plan.days.count - 1)].release.day,
      dayIndex: dayIndex,
      dayCount: plan.days.count,
      bytesRead: tally.completedBytes,
      totalBytes: plan.totalBytes,
      tracesFound: tally.saved
    )
  }

  /// Where an ADS-B download job stands.
  enum State {
    /// No download has run, or its result was dismissed.
    case idle
    /// A day's download is connecting.
    case preparing(DownloadProgress)
    /// Archives are streaming in.
    case downloading(DownloadProgress)
    /// The connection failed and the download is waiting to reconnect.
    case retrying(DownloadProgress, RetryWait)
    /// Every day was downloaded.
    case finished(DownloadSummary)
    /// A day couldn't be downloaded; the days before it were saved.
    case failed(DownloadFailure)
    /// The user stopped the download; the days finished were saved.
    case stopped(DownloadSummary)

    /// How far the download has come, while it runs.
    var progress: DownloadProgress? {
      switch self {
        case .preparing(let progress), .downloading(let progress), .retrying(let progress, _):
          progress
        case .idle, .finished, .failed, .stopped:
          nil
      }
    }
  }

  /// The days a run downloads and the aircraft it looks for.
  private struct Plan {
    let days: [ADSBPlannedDay]
    let addresses: Set<ICAOAddress>

    /// The size of every day's archive, if each one is known.
    var totalBytes: Int64? { ADSBEstimate(days: days).bytes }
  }

  /// What the days finished so far added up to.
  private struct Tally {
    var completedDays = 0
    var completedBytes: Int64 = 0
    var currentDayBytes: Int64 = 0
    var saved = 0
    var downloadedDays = 0
    var daysWithoutTraces = [ADSBArchiveDay]()

    var summary: DownloadSummary {
      DownloadSummary(
        tracesSaved: saved,
        daysDownloaded: downloadedDays,
        daysWithoutTraces: daysWithoutTraces
      )
    }

    mutating func record(_ result: ADSBDayResult, of day: ADSBPlannedDay) {
      completedDays += 1
      completedBytes += day.bytes ?? currentDayBytes
      currentDayBytes = 0
      saved += result.saved
      guard result.wasDownloaded else { return }
      downloadedDays += 1
      if result.saved == 0 { daysWithoutTraces.append(day.release.day) }
    }
  }
}

/// How far a running ADS-B download has come.
struct DownloadProgress: Equatable {
  /// The day being downloaded.
  let day: ADSBArchiveDay
  /// Which day it is, counting from zero.
  let dayIndex: Int
  /// The number of days in the run.
  let dayCount: Int
  /// The bytes downloaded across the run, counting each finished day in full.
  var bytesRead: Int64
  /// The size of the whole run, if every day's size is known.
  let totalBytes: Int64?
  /// How far through the current day the download is, from 0 to 1.
  var dayFraction = 0.0
  /// The traces found across the run.
  var tracesFound: Int

  /// How far through the run the download is, from 0 to 1.
  var fractionCompleted: Double {
    if let totalBytes, totalBytes > 0 { return min(1, Double(bytesRead) / Double(totalBytes)) }
    return (Double(dayIndex) + dayFraction) / Double(max(1, dayCount))
  }
}

/// A retry an ADS-B download is waiting for.
struct RetryWait: Equatable {
  /// Why the connection is being retried.
  let reason: ADSBRetryReason
  /// Which retry in a row this is, counting from one.
  let attempt: Int
  /// When the download reconnects.
  let resumesAt: Date
}

/// What an ADS-B download run saved.
struct DownloadSummary: Equatable {
  /// The traces saved.
  let tracesSaved: Int
  /// The days whose archives were downloaded.
  let daysDownloaded: Int
  /// The downloaded days that had no trace of the chosen aircraft.
  let daysWithoutTraces: [ADSBArchiveDay]
}

/// Why an ADS-B download run failed.
struct DownloadFailure: Equatable {
  /// The day that couldn't be downloaded.
  let day: ADSBArchiveDay
  /// What went wrong, in general.
  let message: String
  /// The particulars, if the error gave any.
  let reason: String?
  /// What the run saved before failing.
  let summary: DownloadSummary

  /// Describes a failed day from its error.
  init(day: ADSBArchiveDay, error: any Error, summary: DownloadSummary) {
    let error = error as NSError
    self.init(
      day: day,
      message: error.localizedDescription,
      reason: [error.localizedFailureReason, error.localizedRecoverySuggestion]
        .compactMap(\.self).joined(separator: " "),
      summary: summary
    )
  }

  /// Describes a failed day.
  init(day: ADSBArchiveDay, message: String, reason: String?, summary: DownloadSummary) {
    self.day = day
    self.message = message
    self.reason = reason?.isEmpty == false ? reason : nil
    self.summary = summary
  }
}

/// A day an ADS-B download covers: its release and, if known, the release's size.
nonisolated struct ADSBPlannedDay: Sendable {
  /// The day's release.
  let release: ADSBRelease
  /// The release's size in bytes, if every part reports one.
  let bytes: Int64?
}

/// The days a download would cover and their combined size.
nonisolated struct ADSBEstimate: Sendable {
  /// The days, in order.
  let days: [ADSBPlannedDay]

  /// Their combined size in bytes, if every day's is known.
  var bytes: Int64? {
    days.reduce(Int64?.some(0)) { total, day in
      total.flatMap { total in day.bytes.map { total + $0 } }
    }
  }
}

/// What downloading one day saved.
nonisolated struct ADSBDayResult: Sendable {
  /// The traces saved.
  let saved: Int
  /// Whether the day's archive was downloaded, rather than skipped because every trace was
  /// already saved.
  let wasDownloaded: Bool
}

/// adsb.lol lookups and downloads, done off the main actor.
nonisolated struct ADSBDayDownload: Sendable {
  let client: ADSBLolClient
  let cache: ADSBTraceCache

  /// Finds the releases for some days and their sizes.
  @concurrent
  func estimate(_ days: [ADSBArchiveDay]) async throws -> ADSBEstimate {
    var planned = [ADSBPlannedDay]()
    for day in days {
      let release = try await client.preferredRelease(on: day)
      planned.append(ADSBPlannedDay(release: release, bytes: try await client.size(of: release)))
    }
    return ADSBEstimate(days: planned)
  }

  /// Downloads a day's traces of the aircraft not yet saved for it, and saves them.
  @concurrent
  func fetch(
    _ day: ADSBPlannedDay,
    for addresses: Set<ICAOAddress>,
    progress: @escaping @Sendable (ADSBFetchProgress) -> Void
  ) async throws -> ADSBDayResult {
    let needed = addresses.filter { !cache.contains(day: day.release.day, icao: $0) }
    guard !needed.isEmpty else { return ADSBDayResult(saved: 0, wasDownloaded: false) }
    let result = try await client.fetchTraces(
      in: day.release,
      for: needed,
      expectedSize: day.bytes,
      progress: progress
    )
    for trace in result.traces { try cache.store(trace) }
    return ADSBDayResult(saved: result.traces.count, wasDownloaded: true)
  }
}
