import Foundation
import Sentry
import Testing

@testable import LogTen_Assistant

struct ReportRedactionTests {
  private static let redacted = ReportRedaction.placeholder

  @Test(
    "Redacts paths, file URLs and addresses",
    arguments: [
      ("Can’t open /Users/pilot/My Logbooks/Main", "Can’t open \(redacted)"),
      ("Missing ~/Library/Group Containers/x", "Missing \(redacted)"),
      ("file:///Users/pilot/Logbook failed", "\(redacted) failed"),
      ("Signed in as pilot@example.com", "Signed in as \(redacted)"),
      ("first /a/b\nsecond /c/d", "first \(redacted)\nsecond \(redacted)")
    ]
  )
  func redactsIdentifyingText(input: String, expected: String) {
    #expect(ReportRedaction.redacted(input) == expected)
  }

  @Test(
    "Leaves text that only looks like a path",
    arguments: ["https://host/route", "and/or", "N/A", "1/2 of flights", "Nothing to redact"]
  )
  func keepsOrdinaryText(input: String) {
    #expect(ReportRedaction.redacted(input) == input)
  }

  @Test
  func redactsEveryStringAnEventCarries() throws {
    let event = Event(level: .error)
    event.message = SentryMessage(formatted: "Opened /Users/pilot/Logbook")
    event.message?.message = "Opened %@"
    event.message?.params = ["/Users/pilot/Logbook"]
    let exception = Exception(value: "No such file /Users/pilot/Logbook", type: "NSError")
    event.exceptions = [exception]
    event.extra = ["path": "/Users/pilot/Logbook", "nested": ["owner": "pilot@example.com"]]
    event.request = SentryRequest()
    event.request?.url = "file:///Users/pilot/Logbook"

    let redacted = ReportRedaction.redacting(event)

    #expect(redacted.message?.formatted == "Opened \(Self.redacted)")
    #expect(redacted.message?.params == [Self.redacted])
    #expect(redacted.exceptions?.first?.value == "No such file \(Self.redacted)")
    #expect(redacted.exceptions?.first?.type == "NSError")
    #expect(redacted.extra?["path"] as? String == Self.redacted)
    let nested = try #require(redacted.extra?["nested"] as? [String: Any])
    #expect(nested["owner"] as? String == Self.redacted)
    #expect(redacted.request?.url == Self.redacted)
  }

  @Test
  func reducesBreadcrumbToItsCategoryTypeAndLevel() {
    let breadcrumb = Breadcrumb(level: .warning, category: "ui.click")
    breadcrumb.type = "user"
    breadcrumb.message = "Opened /Users/pilot/Logbook"
    breadcrumb.data = ["path": "/Users/pilot/Logbook"]

    let reduced = ReportRedaction.redacting(breadcrumb)

    #expect(reduced.category == "ui.click")
    #expect(reduced.type == "user")
    #expect(reduced.level == .warning)
    #expect(reduced.message == nil)
    #expect(reduced.data == nil)
  }
}
