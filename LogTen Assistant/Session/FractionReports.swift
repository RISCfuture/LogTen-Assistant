import LogbookModel

/**
 Runs background work that reports how far it has got, handing each report to the main actor
 in order.

 Reports that arrive faster than the main actor takes them are dropped in favor of the newest.
 Every report is handled by the time this returns, so none can land after the caller moves on.

 - Parameters:
   - deliver: Receives each fraction from 0 to 1 on the main actor.
   - body: The work, given the closure to report through.
 */
nonisolated func withFractionReports<Result>(
  deliveredTo deliver: @escaping @MainActor @Sendable (Double) -> Void,
  body: (@escaping ProgressTally.Report) async throws -> Result
) async rethrows -> Result {
  let (fractions, continuation) = AsyncStream.makeStream(
    of: Double.self,
    bufferingPolicy: .bufferingNewest(1)
  )
  let watcher = Task {
    for await fraction in fractions { await deliver(fraction) }
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
