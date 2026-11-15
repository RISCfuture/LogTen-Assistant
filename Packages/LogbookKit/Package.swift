// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("ImmutableWeakCaptures"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .strictMemorySafety()
]

let measurementKit = Target.Dependency.product(name: "MeasurementKit", package: "MeasurementKit")
let measurementKitLocation = Target.Dependency.product(
  name: "MeasurementKitLocation",
  package: "MeasurementKit"
)
let GRDB = Target.Dependency.product(name: "GRDB", package: "GRDB.swift")

/// A library module with localized resources and the standard Swift settings.
func module(_ name: String, dependencies: [Target.Dependency] = []) -> Target {
  .target(
    name: name,
    dependencies: dependencies,
    resources: [.process("Resources")],
    swiftSettings: swiftSettings
  )
}

/// The Swift Testing target for `module`, which can build synthetic LogTen stores.
func tests(for module: String, fixtures: Bool = false) -> Target {
  .testTarget(
    name: "\(module)Tests",
    dependencies: [.target(name: module), "LogbookTestSupport"],
    resources: fixtures ? [.copy("Fixtures")] : nil,
    swiftSettings: swiftSettings
  )
}

let libraryModules = [
  "LogbookModel", "LogbookStore", "Credentials", "Workspace", "Regulations", "Tracks",
  "FlightSources", "References", "Audit", "Review", "Corrections", "PilotLookup", "AuditWorkflow"
]

let package = Package(
  name: "LogbookKit",
  defaultLocalization: "en",
  platforms: [.macOS(.v27)],
  products: [
    .library(name: "LogbookKit", targets: libraryModules)
  ],
  dependencies: [
    .package(url: "https://github.com/RISCfuture/SwiftNASR.git", from: "5.0.1"),
    .package(url: "https://github.com/RISCfuture/MeasurementKit.git", from: "1.2.1"),
    .package(url: "https://github.com/RISCfuture/StreamingCSV.git", from: "3.0.0"),
    .package(url: "https://github.com/RISCfuture/SwiftCIFP.git", from: "3.0.0"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
    .package(url: "https://github.com/RISCfuture/SwiftAirmen.git", from: "4.0.1"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0")
  ],
  targets: [
    module("LogbookModel", dependencies: [measurementKit]),
    module("LogbookStore", dependencies: ["LogbookModel", "ExceptionCatching", GRDB]),
    module("Credentials"),
    module("Workspace", dependencies: ["LogbookModel", GRDB]),
    module("Regulations", dependencies: ["LogbookModel"]),
    module("Tracks", dependencies: ["LogbookModel", measurementKitLocation]),
    module(
      "FlightSources",
      dependencies: [
        "LogbookModel", "Tracks", "Credentials",
        .product(name: "StreamingCSV", package: "StreamingCSV")
      ]
    ),
    module(
      "References",
      dependencies: [
        "LogbookModel", measurementKitLocation,
        .product(name: "SwiftNASR", package: "SwiftNASR"),
        .product(name: "SwiftCIFP", package: "SwiftCIFP"),
        .product(name: "ZIPFoundation", package: "ZIPFoundation")
      ]
    ),
    module(
      "Audit",
      dependencies: [
        "LogbookModel", "LogbookStore", "Tracks", "FlightSources", "References",
        measurementKitLocation
      ]
    ),
    module("Review", dependencies: ["LogbookModel"]),
    module("Corrections", dependencies: ["LogbookModel", "LogbookStore", GRDB]),
    module(
      "AuditWorkflow",
      dependencies: [
        "LogbookModel", "LogbookStore", "Workspace", "Tracks", "FlightSources", "References",
        "Audit", "Review", "Corrections", .product(name: "SwiftNASR", package: "SwiftNASR")
      ]
    ),
    module(
      "PilotLookup",
      dependencies: ["LogbookModel", .product(name: "SwiftAirmen", package: "SwiftAirmen")]
    ),

    .target(name: "ExceptionCatching"),
    .target(
      name: "LogbookTestSupport",
      dependencies: ["LogbookModel", "LogbookStore"],
      swiftSettings: swiftSettings
    ),

    tests(for: "LogbookModel"),
    tests(for: "LogbookStore"),
    tests(for: "Credentials"),
    tests(for: "Workspace"),
    tests(for: "Regulations"),
    tests(for: "Tracks", fixtures: true),
    tests(for: "FlightSources", fixtures: true),
    tests(for: "References", fixtures: true),
    tests(for: "Audit", fixtures: true),
    tests(for: "Review"),
    tests(for: "Corrections", fixtures: true),
    tests(for: "PilotLookup"),
    tests(for: "AuditWorkflow")
  ],
  swiftLanguageModes: [.v6]
)
