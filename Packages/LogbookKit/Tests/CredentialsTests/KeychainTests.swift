import Credentials
import Foundation
import Testing

/// Uses a service name of its own in the login keychain, since an unsigned test runner has no
/// entitlement for the data-protection keychain.
@Suite(.serialized)
struct `Keychain items` {
  private let keychain = Keychain(
    service: "codes.tim.LogTenAssistant.tests.\(UUID().uuidString)",
    usesDataProtectionKeychain: false
  )

  @Test
  func `stores, replaces and removes a secret`() throws {
    defer { try? keychain.remove(.flyStoAPIToken) }
    #expect(try keychain.string(for: .flyStoAPIToken) == nil)

    try keychain.set("first-token", for: .flyStoAPIToken)
    #expect(try keychain.string(for: .flyStoAPIToken) == "first-token")

    try keychain.set("second-token", for: .flyStoAPIToken)
    #expect(try keychain.string(for: .flyStoAPIToken) == "second-token")

    try keychain.remove(.flyStoAPIToken)
    #expect(try keychain.string(for: .flyStoAPIToken) == nil)
  }

  @Test
  func `keeps accounts apart`() throws {
    defer {
      try? keychain.remove(.openSkyClientID)
      try? keychain.remove(.openSkyClientSecret)
    }
    try keychain.set("client", for: .openSkyClientID)
    try keychain.set("secret", for: .openSkyClientSecret)

    #expect(try keychain.string(for: .openSkyClientID) == "client")
    #expect(try keychain.string(for: .openSkyClientSecret) == "secret")
  }

  @Test
  func `treats removing a missing item as success`() throws {
    try keychain.remove(.flyStoAPIToken)
  }
}
