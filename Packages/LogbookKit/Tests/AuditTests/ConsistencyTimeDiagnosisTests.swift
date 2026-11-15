@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Time diagnosis` {
  private typealias Fixtures = ConsistencyFixtures

  private let diagnosis = TimeDiagnosis(toleranceMinutes: 6, maximumMinutes: 18 * 60)

  private func analysis(
    total: UInt,
    out: Date?,
    in end: Date?,
    remarks: String? = nil
  ) -> FindingAnalysis? {
    diagnosis.analysis(
      of: AuditedFlight(
        Fixtures.flight("F1", day: 1, totalMinutes: total, out: out, in: end) {
          $0.remarks = remarks
        }
      )
    )
  }

  @Test
  func `has nothing to say without out and in times or total time`() {
    #expect(analysis(total: 60, out: Fixtures.time(1, 10), in: nil) == nil)
    #expect(analysis(total: 0, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11)) == nil)
  }

  @Test
  func `offers nothing when the interval agrees within tolerance`() throws {
    let result = try #require(
      analysis(total: 60, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11, 5))
    )

    #expect(result.dateErrorCandidates.isEmpty)
    #expect(result.summary == nil)
  }

  @Test
  func `offers swapping out and in when that fits the total`() throws {
    let result = try #require(
      analysis(total: 60, out: Fixtures.time(1, 11), in: Fixtures.time(1, 10))
    )

    #expect(result.dateErrorCandidates.map(\.swapsOutAndIn) == [true])
    #expect(result.dateErrorCandidates.first?.out == Fixtures.time(1, 10))
    #expect(result.dateErrorCandidates.first?.minutes == 60)
  }

  @Test
  func `matches a total of whole days plus a remainder against the remainder`() throws {
    let result = try #require(
      analysis(total: 1500, out: Fixtures.time(1, 10), in: Fixtures.time(2, 11))
    )

    #expect(result.dateErrorCandidates.map { [$0.outDayShift, $0.inDayShift] } == [[0, -1], [1, 0]])
    #expect(result.dateErrorCandidates.allSatisfy { $0.minutes == 60 })
    let plain = try #require(
      analysis(total: 60, out: Fixtures.time(1, 11), in: Fixtures.time(1, 10))?.summary
    )
    let summary = try #require(result.summary)
    #expect(summary.hasPrefix(plain) && summary.count > plain.count)
  }

  @Test
  func `notes a whole-hour discrepancy when no alternative fits`() throws {
    let result = try #require(
      analysis(total: 60, out: Fixtures.time(1, 10), in: Fixtures.time(1, 12))
    )

    #expect(result.dateErrorCandidates.isEmpty)
    #expect(result.summary?.isEmpty == false)
  }

  @Test
  func `stays quiet about a discrepancy that is not a whole number of hours`() throws {
    let result = try #require(
      analysis(total: 60, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11, 30))
    )

    #expect(result.dateErrorCandidates.isEmpty)
    #expect(result.summary == nil)
  }

  @Test
  func `calls it partial credit only when the logged time is the shorter`() throws {
    let remarks = "Safety pilot"
    let shorter = try #require(
      analysis(total: 30, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11), remarks: remarks)
    )
    let longer = try #require(
      analysis(total: 90, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11), remarks: remarks)
    )
    let unrelated = try #require(
      analysis(total: 30, out: Fixtures.time(1, 10), in: Fixtures.time(1, 11), remarks: "Local")
    )

    let misdated = try #require(
      analysis(total: 30, out: Fixtures.time(1, 10), in: Fixtures.time(2, 11), remarks: remarks)
    )

    #expect(shorter.isPartialCredit)
    #expect(!longer.isPartialCredit)
    #expect(!misdated.isPartialCredit)
    #expect(!unrelated.isPartialCredit)
  }
}
