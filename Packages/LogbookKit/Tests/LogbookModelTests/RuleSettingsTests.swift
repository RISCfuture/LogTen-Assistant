import Foundation
import LogbookModel
import Testing

@Suite
struct `Rule switches` {
  private let rule = RuleID(rawValue: "future_date")

  @Test
  func `run a rule on by default until it is turned off, and one off by default once turned on`() {
    var settings = RuleSettings()
    #expect(settings.isEnabled(rule))
    #expect(!settings.isEnabled(rule, byDefault: false))

    settings.setEnabled(false, rule)
    settings.setEnabled(true, rule, byDefault: false)

    #expect(!settings.isEnabled(rule))
    #expect(settings.isEnabled(rule, byDefault: false))
    #expect(settings.disabledRules == [rule] && settings.enabledRules == [rule])
  }

  @Test
  func `decode settings saved without rules turned on`() throws {
    var saved =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(RuleSettings(disabledRules: [rule]))
      ) as? [String: Any]
    saved?["enabledRules"] = nil
    let data = try JSONSerialization.data(withJSONObject: try #require(saved))

    let settings = try JSONDecoder().decode(RuleSettings.self, from: data)

    #expect(settings == RuleSettings(disabledRules: [rule]))
  }
}
