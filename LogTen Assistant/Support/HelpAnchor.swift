import SwiftUI

/**
 A named place in the app's help book.

 Every help affordance names one of these rather than a bare string. The anchors themselves are
 `<a name="…">` elements in the HTML under `Help/LogTen Assistant.help`, and nothing at compile
 time can catch a typo: a misspelled anchor doesn't fail, it silently opens the book's first page
 instead of the topic that was asked for. Naming them once here is what lets
 `Scripts/build-help-book.sh` check each one against the book it is about to ship, and fail the
 build when the two disagree.

 The raw values name the topic rather than the control that points at it, so moving a control
 between screens never invalidates an anchor. They are identifiers, not prose, and are never
 translated.
 */
enum HelpAnchor: String, Sendable {
  /// Opening a logbook and finding your way around the window.
  case gettingStarted = "getting-started"

  /// Why the app reads a copy of the logbook and never the live store.
  case snapshots = "snapshots"

  /// The pages of findings and what each one compares.
  case auditAndFix = "audit-and-fix"

  /// Making decisions on findings.
  case reviewingFindings = "reviewing-findings"

  /// Preflight, backup, the pilot batch, verification, and recording versus sending.
  case applyingFixes = "applying-fixes"

  /// Undoing an applied batch from Applied History.
  case revertingABatch = "reverting-a-batch"

  /// The currency-rule violations.
  case violations = "violations"

  /// The Data Sources page.
  case dataSources = "data-sources"

  /// FlySto tokens, sync, CSV import and data-log upload.
  case flySto = "flysto"

  /// Downloading ADS-B traces.
  case adsbData = "adsb-data"

  /// FAA NASR and CIFP data.
  case faaData = "faa-data"

  /// The per-logbook settings sheet.
  case logbookSettings = "logbook-settings"

  /// The app-wide Settings window.
  case appSettings = "app-settings"

  /// Checking for new versions.
  case updates = "updates"

  /// What the app sends off the Mac.
  case privacyAndData = "privacy-and-data"
}

/// The system help button, a circled question mark, pointed at one topic in the help book.
///
/// Wraps `HelpLink`, which is the real AppKit control, and adds the help tag and accessibility
/// identifier that `HelpLink` leaves identical across every button on screen.
struct HelpTopicLink: View {
  /// The topic in the book this button opens.
  let anchor: HelpAnchor

  /// The button's identifier, in the app's `<screen>.<control>` scheme.
  let accessibilityIdentifier: String

  var body: some View {
    HelpLink(anchor: anchor.rawValue)
      .help("Open this topic in LogTen Assistant Help")
      .accessibilityIdentifier(accessibilityIdentifier)
  }
}
