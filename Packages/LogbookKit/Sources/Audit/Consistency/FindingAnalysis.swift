public import Foundation
public import LogbookModel

/**
 Explanation attached to a finding that helps the reviewer decide it, without proposing a
 change.

 Analyses are not part of a finding's evidence, so they don't affect its identifier: the same
 finding may be explained differently as the explanations improve.
 */
public struct FindingAnalysis: Hashable, Codable, Sendable {
  /// A one-paragraph explanation, if the analysis reached one.
  public var summary: String?

  /// Further notes for the reviewer.
  public var notes: [String]

  /// Whether the remarks describe partial-flight credit, such as safety-pilot time, so the
  /// logged time need not match the aircraft's elapsed time.
  public var isPartialCredit: Bool

  /// Alternative out and in times that would fit the logged total time.
  public var dateErrorCandidates: [DateErrorCandidate]

  /// Other findings that may share this one's cause.
  public var relatedFindings: [FindingID]

  /// Creates an analysis.
  public init(
    summary: String? = nil,
    notes: [String] = [],
    isPartialCredit: Bool = false,
    dateErrorCandidates: [DateErrorCandidate] = [],
    relatedFindings: [FindingID] = []
  ) {
    self.summary = summary
    self.notes = notes
    self.isPartialCredit = isPartialCredit
    self.dateErrorCandidates = dateErrorCandidates
    self.relatedFindings = relatedFindings
  }
}

/**
 An alternative reading of a flight's out and in times, produced by shifting either by whole
 days or swapping them, that matches the logged total time.

 Candidates are possibilities to check against recordings and adjacent entries, never
 corrections: arithmetic alone can't tell which endpoint or date is wrong.
 */
public struct DateErrorCandidate: Hashable, Codable, Sendable {
  /// The alternative block-out time.
  public var out: Date

  /// The alternative block-in time.
  public var `in`: Date

  /// The block time the alternative implies, in minutes.
  public var minutes: Double

  /// Whether the alternative swaps out and in.
  public var swapsOutAndIn: Bool

  /// How many days the out time moves.
  public var outDayShift: Int

  /// How many days the in time moves.
  public var inDayShift: Int

  /// How far the alternative is from the logged times: one per swap and one per day moved.
  public var cost: Int {
    (swapsOutAndIn ? 1 : 0) + abs(outDayShift) + abs(inDayShift)
  }

  /// Creates a candidate.
  public init(
    out: Date,
    in: Date,
    minutes: Double,
    swapsOutAndIn: Bool,
    outDayShift: Int,
    inDayShift: Int
  ) {
    self.out = out
    self.in = `in`
    self.minutes = minutes
    self.swapsOutAndIn = swapsOutAndIn
    self.outDayShift = outDayShift
    self.inDayShift = inDayShift
  }
}
