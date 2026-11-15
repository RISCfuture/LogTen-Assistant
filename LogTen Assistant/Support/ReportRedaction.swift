import Foundation
import Sentry

/// Strips from a crash report what could identify the pilot or the contents of a logbook.
///
/// A path is taken to run to the end of its line, because a folder name may contain spaces and
/// nothing in the surrounding text says where one stops. A message that mentions a path early
/// therefore loses the rest of its sentence. Issues are grouped by exception type and stack
/// trace, which redaction leaves alone.
nonisolated enum ReportRedaction {
  /// What every redacted run is replaced with.
  static let placeholder = "⟨redacted⟩"

  /// A `file:` URL. Matched before ``path``, which cannot see one.
  nonisolated(unsafe) private static let fileURL = #/file:/\S*/#

  /// An email address, which is how an OpenSky or FlySto account names its owner.
  nonisolated(unsafe) private static let email =
    #/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#

  /// An absolute or home-relative path, and the rest of the line it sits on.
  ///
  /// The leading group keeps the rule out of `https://host/route`, `and/or`, `N/A` and `1/2`: a
  /// slash that follows a colon, another slash, or a word character does not open a match.
  nonisolated(unsafe) private static let path = #/(?<lead>^|[^:/\w~])(?:~?/[^\s/][^\n]*)/#

  /// The event with every string that could carry a path or address redacted. An event is
  /// never discarded: a crash whose message is gone is still the crash.
  static func redacting(_ event: Event) -> Event {
    event.message = event.message.map(redacting)
    event.exceptions = event.exceptions?.map(redacting)
    event.breadcrumbs = event.breadcrumbs?.map(redacting)
    event.extra = event.extra?.mapValues(redactedValue)
    event.request?.url = event.request?.url.map(redacted)
    return event
  }

  /// The breadcrumb reduced to its category, type and level. The message and data of a
  /// breadcrumb can carry anything the logbook held.
  static func redacting(_ breadcrumb: Breadcrumb) -> Breadcrumb {
    let reduced = Breadcrumb(level: breadcrumb.level, category: breadcrumb.category)
    reduced.type = breadcrumb.type
    reduced.timestamp = breadcrumb.timestamp
    return reduced
  }

  /// The string with every path and address in it replaced.
  static func redacted(_ string: String) -> String {
    var redacted = string.replacing(unsafe fileURL, with: placeholder)
    redacted = redacted.replacing(unsafe email, with: placeholder)
    return redacted.replacing(unsafe path) { "\($0.lead)\(placeholder)" }
  }

  private static func redacting(_ message: SentryMessage) -> SentryMessage {
    let redacted = SentryMessage(formatted: self.redacted(message.formatted))
    redacted.message = message.message.map(self.redacted)
    redacted.params = message.params?.map(self.redacted)
    return redacted
  }

  private static func redacting(_ exception: Exception) -> Exception {
    exception.value = exception.value.map(redacted)
    return exception
  }

  private static func redactedValue(_ value: Any) -> Any {
    switch value {
      case let string as String: redacted(string)
      case let values as [String: Any]: values.mapValues(redactedValue)
      case let values as [Any]: values.map(redactedValue)
      default: value
    }
  }
}
