import Testing

@testable import LogTen_Assistant

@MainActor
struct FractionReportsTests {
  @Test
  func deliversTheNewestReportBeforeReturningTheResult() async {
    let delivered = Delivered()
    let result = await withFractionReports(deliveredTo: delivered.record) { report in
      for fraction in stride(from: 0.1, through: 1.0, by: 0.1) { report(fraction) }
      return "done"
    }
    #expect(result == "done")
    #expect(delivered.fractions.last == 1.0)
  }

  @Test
  func deliversEveryReportBeforeRethrowingAFailure() async {
    let delivered = Delivered()
    await #expect(throws: Failure.self) {
      try await withFractionReports(deliveredTo: delivered.record) { report in
        report(0.5)
        throw Failure()
      }
    }
    #expect(delivered.fractions == [0.5])
  }

  @MainActor
  private final class Delivered {
    var fractions = [Double]()

    var record: @MainActor @Sendable (Double) -> Void {
      { [self] in fractions.append($0) }
    }
  }

  private struct Failure: Error {}
}
