import FlightSources
import SwiftUI

/// The ADS-B download on the Data Sources page: its progress and Stop while it runs, then
/// what it saved, or why it failed with Retry.
struct ADSBDownloadRow: View {
  let state: ADSBDownloadJob.State
  let canResume: Bool
  let actions: ADSBDownloadActions

  var body: some View {
    switch state {
      case .idle:
        EmptyView()
      case .preparing(let progress):
        RunningDownload(progress: progress, retry: nil, isConnecting: true, stop: actions.stop)
      case .downloading(let progress):
        RunningDownload(progress: progress, retry: nil, isConnecting: false, stop: actions.stop)
      case let .retrying(progress, retry):
        RunningDownload(progress: progress, retry: retry, isConnecting: false, stop: actions.stop)
      case .finished(let summary):
        EndedDownload(actions: actions, canResume: false) {
          SummaryText(summary: summary)
        }
      case .failed(let failure):
        EndedDownload(actions: actions, canResume: canResume) {
          FailureText(failure: failure)
        }
      case .stopped(let summary):
        EndedDownload(actions: actions, canResume: canResume) {
          Text("Download stopped.")
          if summary.tracesSaved > 0 { SummaryText(summary: summary).foregroundStyle(.secondary) }
        }
    }
  }

  /// Creates a row for a session's download job.
  init(job: ADSBDownloadJob) {
    state = job.state
    canResume = job.canResume
    actions = ADSBDownloadActions(
      stop: { job.stop() },
      retry: { job.retry() },
      dismiss: { job.dismiss() }
    )
  }

  /// Creates a row for a download state.
  init(state: ADSBDownloadJob.State, canResume: Bool, actions: ADSBDownloadActions) {
    self.state = state
    self.canResume = canResume
    self.actions = actions
  }
}

/// What the row's buttons do.
struct ADSBDownloadActions {
  /// Buttons that do nothing, for previews.
  static let none = Self(stop: {}, retry: {}, dismiss: {})

  /// Stops the running download.
  let stop: () -> Void
  /// Carries on from the first day not downloaded.
  let retry: () -> Void
  /// Clears the result of a download that ended.
  let dismiss: () -> Void
}

/// A download in progress: the day, a progress bar, the bytes or the retry, and Stop.
private struct RunningDownload: View {
  let progress: DownloadProgress
  let retry: RetryWait?
  let isConnecting: Bool
  let stop: () -> Void

  var body: some View {
    HStack {
      ProgressView(value: progress.fractionCompleted) {
        Text(
          "\(progress.day.start, format: LogbookFormat.utcDay) · day \(progress.dayIndex + 1, format: .number) of \(progress.dayCount, format: .number)"
        )
        .environment(\.timeZone, .gmt)
      } currentValueLabel: {
        if let retry {
          RetryCountdown(retry: retry)
        } else if isConnecting {
          Text("Connecting…")
        } else {
          TransferText(progress: progress)
        }
      }
      .accessibilityIdentifier("dataSources.adsbProgress")
      Button("Stop", action: stop)
        .accessibilityIdentifier("dataSources.adsbStop")
    }
  }
}

/// The bytes downloaded and the traces found, such as “1.2 GB of 3.1 GB · 2 traces found”.
private struct TransferText: View {
  let progress: DownloadProgress

  var body: some View {
    if let total = progress.totalBytes {
      Text(
        "\(progress.bytesRead, format: .byteCount(style: .file)) of \(total, format: .byteCount(style: .file)) · \(progress.tracesFound) traces found"
      )
    } else {
      Text(
        "\(progress.bytesRead, format: .byteCount(style: .file)) · \(progress.tracesFound) traces found"
      )
    }
  }
}

/// Why the download is waiting and how long until it reconnects, counting down.
private struct RetryCountdown: View {
  let retry: RetryWait

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = retry.resumesAt.timeIntervalSince(context.date).rounded(.up)
      if remaining > 0 {
        Text(
          "\(retry.reason.description). Retrying in \(Duration.seconds(remaining), format: .units(allowed: [.minutes, .seconds], width: .narrow))…"
        )
      } else {
        Text("\(retry.reason.description). Reconnecting…")
      }
    }
    .accessibilityIdentifier("dataSources.adsbRetrying")
  }
}

/// A download that ended: what it says, then Retry if days are left, and Dismiss.
private struct EndedDownload<Message: View>: View {
  let actions: ADSBDownloadActions
  let canResume: Bool
  @ViewBuilder let message: Message

  var body: some View {
    HStack {
      VStack(alignment: .leading) { message }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dataSources.adsbResult")
      Spacer()
      if canResume {
        Button("Retry", action: actions.retry)
          .accessibilityIdentifier("dataSources.adsbRetry")
      }
      Button("Dismiss", action: actions.dismiss)
        .accessibilityIdentifier("dataSources.adsbDismiss")
    }
  }
}

/// What a run saved, such as “Saved 4 traces from 3 days.”
private struct SummaryText: View {
  let summary: DownloadSummary

  var body: some View {
    Text(
      "Saved \(summary.tracesSaved) traces from \(summary.daysDownloaded) days."
    )
    if !summary.daysWithoutTraces.isEmpty {
      Text(
        "\(summary.daysWithoutTraces.count) days had no trace of the chosen aircraft."
      )
      .foregroundStyle(.secondary)
    }
  }
}

/// Which day failed and why.
private struct FailureText: View {
  let failure: DownloadFailure

  var body: some View {
    Label {
      Text("Couldn’t download \(failure.day.start, format: LogbookFormat.utcDay).")
        .environment(\.timeZone, .gmt)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
        .symbolRenderingMode(.multicolor)
        .accessibilityLabel("Warning")
    }
    Text(failure.reason ?? failure.message)
      .foregroundStyle(.secondary)
    if failure.summary.tracesSaved > 0 {
      SummaryText(summary: failure.summary).foregroundStyle(.secondary)
    }
  }
}

#Preview("Connecting") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(
        state: .preparing(PreviewHelper.adsbProgress),
        canResume: false,
        actions: .none
      )
    }
  }
}

#Preview("Downloading") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(
        state: .downloading(PreviewHelper.adsbProgress),
        canResume: false,
        actions: .none
      )
    }
  }
}

#Preview("Retrying") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(
        state: .retrying(PreviewHelper.adsbProgress, PreviewHelper.adsbRetry),
        canResume: false,
        actions: .none
      )
    }
  }
}

#Preview("Failed") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(state: .failed(PreviewHelper.adsbFailure), canResume: true, actions: .none)
    }
  }
}

#Preview("Stopped") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(state: .stopped(PreviewHelper.adsbSummary), canResume: true, actions: .none)
    }
  }
}

#Preview("Finished") {
  PageFormPreview {
    Section("ADS-B") {
      ADSBDownloadRow(state: .finished(PreviewHelper.adsbSummary), canResume: false, actions: .none)
    }
  }
}
