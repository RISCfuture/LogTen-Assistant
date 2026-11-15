# LogTen Assistant

[![CI](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/ci.yml/badge.svg)](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/ci.yml)
[![Linters](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/lint.yml/badge.svg)](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/lint.yml)
[![Periphery](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/periphery.yml/badge.svg)](https://github.com/RISCfuture/LogTen-Assistant/actions/workflows/periphery.yml)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A Mac app that audits a [LogTen](https://coradine.com) logbook. Each logbook opens in its own
window with two workflows:

- **Audit & Fix** compares entries with each other, with the logbook's smart groups, and with
  what the aircraft recorded (FlySto and ADS-B). You review the proposed fixes, approve some,
  back the logbook up, and apply them through LogTen's import. Each batch is then verified.
- **Violations** lists the flights that break the pilot-currency rules of 14 CFR part 61. It
  only reports; nothing is corrected.

The app is sandboxed. It reads LogTen's logbook only after you choose its folder, and it only
ever reads snapshot copies, never the live store.

## Installing

Download the notarized disk image from the
[latest release](https://github.com/RISCfuture/LogTen-Assistant/releases/latest) and drag
LogTen Assistant to Applications. Or install it with Homebrew:

```sh
brew install --cask riscfuture/tap/logten-assistant
```

The app checks GitHub for newer releases and offers to download them.

## Requirements

- macOS 27 to run; Xcode 27.2 (Swift 6.4) to build.
- LogTen installed in `/Applications`, which provides the Core Data model the reader uses.

## Layout

| Path | Contents |
| --- | --- |
| `LogTen Assistant/` | The SwiftUI app: windows, menus, settings, the Apply sheet and App Intents. |
| `LogTen AssistantUITests/` | XCUITest flows, with screen objects built on XCUITestKit. |
| `Packages/LogbookKit/` | The logic, as a local Swift package with one module per concern. |

LogbookKit's modules:

| Module | Responsibility |
| --- | --- |
| `LogbookModel` | Value types for records, settings and findings. |
| `LogbookStore` | Finding logbooks, snapshotting them, and reading snapshots with LogTen's model. |
| `Credentials` | Keychain storage for the FlySto token and OpenSky credentials. |
| `Workspace` | The per-logbook database of settings, evidence, decisions and the apply journal. |
| `Regulations` | The eleven part 61 currency checks. |
| `Tracks` | Track samples, event detection and segmentation. |
| `FlightSources` | FlySto (API, CSV export, log upload), adsb.lol and OpenSky. |
| `References` | FAA NASR airports, CIFP approaches, airport time zones and night. |
| `Audit` | Consistency, smart-group, evidence, night, geography and navigation audits. |
| `Review` | Review decisions and their carry-forward between runs. |
| `Corrections` | Proposals, preflight, import packages, writers, verification, backup and the journal. |
| `PilotLookup` | Filling the pilot profile from the FAA airmen database. |
| `AuditWorkflow` | Running a whole audit, the review queues, exports, and planning and delivering fixes. |

Each module has a DocC catalog; build the documentation with
`xcodebuild docbuild -scheme LogbookKit` from `Packages/LogbookKit`.

## Building and testing

Use your own DerivedData so parallel builds don't collide:

```sh
swift test --package-path Packages/LogbookKit

xcodebuild -project "LogTen Assistant.xcodeproj" -scheme "LogTen Assistant" \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages \
  test | xcbeautify

swiftlint lint --strict
```

The package tests build synthetic stores with LogTen's model, and skip those tests when LogTen
isn't installed. No test reads a real logbook or reaches the network.

The UI tests launch debug builds with these arguments:

- `-UITestFixture sample` opens a built-in synthetic logbook instead of a real one.
- `-UITestStubs flysto` answers FlySto syncs with a stubbed log of the sample's Monterey flight,
  and keeps downloads in a temporary folder.

## Applying fixes safely

Applying is deliberately hard to do by accident:

- **Preflight.** Approved fixes are checked against a fresh snapshot. Entries that are locked,
  signed, have no flight key or changed since the audit are left out and listed on a manual
  checklist instead.
- **Backup.** Applying needs a fresh copy of the whole logbook folder, made by the app with a
  manifest of SHA-256 hashes, plus your confirmation that you made a LogTen backup too.
- **Pilot batch.** A one-flight pilot batch goes first. Each batch is then verified against a new
  snapshot, and journaled with a compensating batch for Revert Batch.
- **Verified fields.** Corrections change only the fields in the allowlist, which are the ones
  validated against LogTen's import; see [LogTen import validation](docs/LogTenImportValidation.md).
- **Recording by default.** Packages are recorded to disk, not sent to LogTen. Sending them
  needs both of these:
  - Settings ▸ Advanced set to *Send to LogTen*;
  - the hidden `DisposableLogbookOpen` default, which declares that LogTen has a disposable
    logbook open.

  The sample logbook always records. Debug builds also need that declaration for the
  `LiveWriteAuthorization` that sending requires.

## Data sources

- **FlySto**: add an API token from flysto.net/account/api in Settings ▸ Accounts. Sync fetches
  the logs added since the last sync. You can also import, or drop on the window, a FlySto CSV
  export with a Safari web archive of its flight list.
- **ADS-B**: Audit ▸ Fetch ADS-B Data… streams adsb.lol's daily archives, which are several
  gigabytes each, and keeps only your aircraft's traces. The data is licensed under the ODbL.
- **FAA data**: Audit ▸ Update NASR Data… downloads the current 28-day cycle. For approach
  naming, add the unzipped `FAACIFP18` file in Data Sources.

## Crash reporting

[Sentry](https://sentry.io) is wired into release builds only; debug builds and test runs
never send events. Reports carry no personal information.

## Releasing

A release is a commit titled "Release X.Y" that advances `MARKETING_VERSION`, beside a
`## X.Y` section in `CHANGELOG.md`, tagged `X.Y` on `main` or on a `release/X.Y` branch for
a hotfix. The tag carries no `v` prefix, because the update checker compares tags against
`CFBundleShortVersionString`.

Pushing the tag runs the Release workflow. It refuses a tag the project's version doesn't
match, archives the app, notarizes it, packages it as a disk image, publishes a GitHub
release with that image and the changelog section as its notes, and asks
[the Homebrew tap](https://github.com/RISCfuture/homebrew-tap) to bump its cask. The build
number is the UTC time of the run, as `YYYYMMDDHHMM`.

To build the same disk image locally:

```sh
bundle exec fastlane download_release
```

Signing credentials come from the private `RISCfuture/certificates` repository via
[fastlane match](https://docs.fastlane.tools/actions/match/). Locally, copy
`fastlane/.env.example` to `fastlane/.env` and fill it in. On CI the same names arrive as
repository secrets: `CERTIFICATES_TOKEN`, `MATCH_PASSWORD`, and `SENTRY_AUTH_TOKEN`, with
`HOMEBREW_TAP_TOKEN` for the cask bump: a fine-grained token limited to
`RISCfuture/homebrew-tap` with Contents read and write.

## Privacy

See the [privacy policy](https://riscfuture.github.io/LogTen-Assistant/privacy.html) for
what the app stores on your Mac and what the data sources above are sent.

## License

LogTen Assistant is licensed under the [MIT License](LICENSE). Its dependencies and data
sources carry their own terms; see [CREDITS.md](CREDITS.md).

LogTen Assistant is not affiliated with, endorsed by, or sponsored by Coradine Aviation
Systems. LogTen and LogTen Pro are trademarks of Coradine Aviation Systems.
