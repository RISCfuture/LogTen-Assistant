import LogbookModel
import Synchronization
import Testing

private final class Reports: Sendable {
  private let fractions = Mutex([Double]())

  var all: [Double] { fractions.withLock { $0 } }
  var report: ProgressTally.Report {
    { fraction in self.fractions.withLock { $0.append(fraction) } }
  }
}

@Suite
struct `Progress tally` {
  @Test
  func `reports the start and then each whole percent once`() {
    let reports = Reports()
    var tally = ProgressTally(total: 1_000, report: reports.report)

    for _ in 0..<1_000 { tally.advance() }

    #expect(reports.all.count == 101)
    #expect(reports.all.first == 0)
    #expect(reports.all.last == 1)
    #expect(reports.all == reports.all.sorted())
  }

  @Test
  func `never reports more than finished when work overshoots`() {
    let reports = Reports()
    var tally = ProgressTally(total: 4, report: reports.report)

    tally.advance(by: 10)

    #expect(reports.all == [0, 1])
    #expect(tally.completed == 4)
  }

  @Test
  func `reports nothing for no work`() {
    let reports = Reports()
    var tally = ProgressTally(total: 0, report: reports.report)

    tally.advance()

    #expect(reports.all.isEmpty)
  }
}
