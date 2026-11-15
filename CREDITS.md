# Credits

LogTen Assistant itself is licensed under the [MIT License](LICENSE). The components
below carry their own terms.

## Apache-2.0 notices

Section 4(d) of the Apache License 2.0 attaches a notice obligation on binary
distribution, so these are called out explicitly rather than left to the list below.

- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)** —
  Copyright the Swift project authors. Licensed under the Apache License, Version 2.0,
  with the Swift Runtime Library Exception.
- **[swift-numerics](https://github.com/apple/swift-numerics)** — Copyright the Swift
  Numerics project authors. Licensed under the Apache License, Version 2.0, with the
  Swift Runtime Library Exception.
- **[swift-syntax](https://github.com/swiftlang/swift-syntax)** — Copyright the Swift
  project authors. Licensed under the Apache License, Version 2.0, with the Swift
  Runtime Library Exception. A build-time dependency of the macros in Defaults and
  StreamingCSV.
- **[swift-macro-toolkit](https://github.com/stackotter/swift-macro-toolkit)** by
  stackotter — Licensed under the Apache License, Version 2.0, with no exception. A
  build-time dependency of the macros in StreamingCSV.
- **[swift-log](https://github.com/apple/swift-log)** — Copyright 2018–2019 The SwiftLog
  Project. Licensed under the Apache License, Version 2.0, with no exception. It contains
  a derivation of the lock implementation from
  [SwiftNIO](https://github.com/apple/swift-nio), also Apache-2.0. Via
  GitHubUpdateChecker.

The Runtime Library Exception waives the attribution that sections 4(a), 4(b), and 4(d)
would otherwise require for portions of those libraries embedded into a binary product.
They are listed here regardless.

The full text of the Apache License, Version 2.0 is available at
<https://www.apache.org/licenses/LICENSE-2.0>.

## Swift packages

Direct dependencies of LogTen Assistant:

- [GRDB.swift](https://github.com/groue/GRDB.swift) by Gwendal Roué — MIT. The SQLite
  layer under the per-logbook workspace and the LogTen store reader.
- [MeasurementKit](https://github.com/RISCfuture/MeasurementKit) — MIT.
- [StreamingCSV](https://github.com/RISCfuture/StreamingCSV) — MIT.
- [SwiftNASR](https://github.com/RISCfuture/SwiftNASR) — MIT. Reads the FAA's NASR
  airport data.
- [SwiftCIFP](https://github.com/RISCfuture/SwiftCIFP) — MIT. Reads the FAA's CIFP
  approach data.
- [SwiftAirmen](https://github.com/RISCfuture/SwiftAirmen) — MIT. Reads the FAA airmen
  database.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) by Thomas Zoechling — MIT.
- [GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker) — MIT.
- [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) — MIT. Crash reporting.
- [XCUITestKit](https://github.com/RISCfuture/XCUITestKit) — MIT. Test-only; not shipped
  in the app.

Pulled in transitively:

- [Defaults](https://github.com/sindresorhus/Defaults) by Sindre Sorhus — MIT. Via
  MeasurementKit.
- [swift-numerics](https://github.com/apple/swift-numerics) — Apache-2.0 with the Swift
  Runtime Library Exception. Via MeasurementKit.
- [swift-syntax](https://github.com/swiftlang/swift-syntax) — Apache-2.0 with the Swift
  Runtime Library Exception. Via Defaults and StreamingCSV.
- [swift-macro-toolkit](https://github.com/stackotter/swift-macro-toolkit) —
  Apache-2.0. Via StreamingCSV.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) —
  Apache-2.0 with the Swift Runtime Library Exception. Via the command-line tools of
  SwiftNASR, SwiftCIFP, and SwiftAirmen.
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) by Guillermo
  Gonzalez — MIT. Via GitHubUpdateChecker.
- [NetworkImage](https://github.com/gonzalezreal/NetworkImage) by Guille Gonzalez — MIT.
  Via swift-markdown-ui.
- [swift-cmark](https://github.com/swiftlang/swift-cmark) — **BSD 2-Clause**, Copyright
  © 2014 John MacFarlane. Via swift-markdown-ui. Not Apache-2.0: the Swift fork carries
  upstream cmark's BSD 2-Clause terms, and portions derived from
  [houdini](https://github.com/vmg/houdini), GitHub's buffer code, and
  [utf8proc](https://juliastrings.github.io/utf8proc/) are MIT.
- [swift-log](https://github.com/apple/swift-log) — Apache-2.0. Via GitHubUpdateChecker.

Every version is pinned in
`LogTen Assistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
and `Packages/LogbookKit/Package.resolved`. The licenses above were read from the
repositories at those exact pinned versions, except sentry-cocoa, GitHubUpdateChecker,
and their dependencies, which are not yet pinned there and are taken from the
licenses of the releases other apps in this family already ship.

## Data

- **[adsb.lol](https://www.adsb.lol)** — ADS-B history is streamed from adsb.lol's daily
  archives. The data is licensed under the
  [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/);
  attribution to adsb.lol is required. The app keeps only your own aircraft's traces.
- **[OpenSky Network](https://opensky-network.org)** — Flight tracks are fetched from
  the OpenSky Network's API under its
  [terms of use](https://opensky-network.org/about/terms-of-use), with your own OpenSky
  credentials where you supply them.
- **[FlySto](https://www.flysto.net)** — Flight logs are fetched from your own FlySto
  account through its API, with a token you provide. LogTen Assistant is not affiliated
  with FlySto.
- **FAA NASR and CIFP** — Airport data from the National Airspace System Resource
  (NASR) subscription and approach data from the Coded Instrument Flight Procedures
  (CIFP) are published by the U.S. Federal Aviation Administration. They are works of
  the U.S. government and in the public domain.

## LogTen

LogTen Assistant is an independent tool that reads LogTen logbooks. It is **not
affiliated with, endorsed by, or sponsored by Coradine Aviation Systems**, and bundles
no Coradine code. It uses the Core Data model that an installed copy of LogTen
provides. LogTen and LogTen Pro are trademarks of Coradine Aviation Systems.
