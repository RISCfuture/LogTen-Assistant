/// Counts finished units of work and reports how far along they are, at most once per whole
/// percent.
///
/// A tally reports `0` when it is created, so a display can switch from indeterminate to
/// determinate as soon as the total is known.
public struct ProgressTally: Sendable {
  /// A callback receiving the fraction of the work finished, from `0` to `1`.
  public typealias Report = @Sendable (Double) -> Void

  private static let percentScale = 100.0

  /// How many units make up the whole job.
  public let total: Int

  /// How many units are finished.
  public private(set) var completed = 0

  private let report: Report?
  private var reportedPercent = -1

  /// Creates a tally and reports its starting point.
  ///
  /// - Parameters:
  ///   - total: The units of work in the whole job. A tally with no work reports nothing.
  ///   - report: Where to send the fraction finished, or `nil` to count silently.
  public init(total: Int, report: Report?) {
    self.total = total
    self.report = report
    announce()
  }

  /// Records finished work, reporting if it moved the fraction into a new percent.
  public mutating func advance(by units: Int = 1) {
    completed = min(total, completed + units)
    announce()
  }

  private mutating func announce() {
    guard total > 0 else { return }
    let fraction = Double(completed) / Double(total)
    let percent = Int((fraction * Self.percentScale).rounded(.down))
    guard percent != reportedPercent else { return }
    reportedPercent = percent
    report?(fraction)
  }
}
