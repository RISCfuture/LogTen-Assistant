public import Foundation
import Security

/// Generic-password items in the Keychain, such as API tokens and client secrets.
///
/// Items are stored in the data-protection keychain under one service name, so the app's
/// secrets stay separate from other apps' and a test can use a service name of its own.
public struct Keychain: Sendable {
  /// The service name the app's items are stored under.
  public static let appService = "codes.tim.LogTenAssistant"

  /// The service name items are stored under.
  public let service: String

  /// Whether items go in the data-protection keychain. Signed, entitled apps should always
  /// use it; unsigned test runners can't, and use the file-based login keychain instead.
  public let usesDataProtectionKeychain: Bool

  /// Creates a keychain for a service.
  public init(service: String = Self.appService, usesDataProtectionKeychain: Bool = true) {
    self.service = service
    self.usesDataProtectionKeychain = usesDataProtectionKeychain
  }

  /// Returns the data stored for an account, or `nil` if there is none.
  public func data(for account: Account) throws(KeychainError) -> Data? {
    var query = baseQuery(for: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
      case errSecSuccess:
        guard let data = result as? Data else { throw .unexpectedData }
        return data
      case errSecItemNotFound:
        return nil
      default:
        throw .unexpectedStatus(status)
    }
  }

  /// Returns the text stored for an account, or `nil` if there is none.
  public func string(for account: Account) throws(KeychainError) -> String? {
    guard let data = try data(for: account) else { return nil }
    guard let string = String(data: data, encoding: .utf8) else { throw .unexpectedData }
    return string
  }

  /// Stores data for an account, replacing any existing value.
  public func set(_ data: Data, for account: Account) throws(KeychainError) {
    let query = baseQuery(for: account)
    let update = [kSecValueData as String: data] as CFDictionary
    let status = SecItemUpdate(query as CFDictionary, update)
    switch status {
      case errSecSuccess:
        return
      case errSecItemNotFound:
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw .unexpectedStatus(addStatus) }
      default:
        throw .unexpectedStatus(status)
    }
  }

  /// Stores text for an account, replacing any existing value.
  public func set(_ string: String, for account: Account) throws(KeychainError) {
    try set(Data(string.utf8), for: account)
  }

  /// Removes an account's item, if there is one.
  public func remove(_ account: Account) throws(KeychainError) {
    let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw .unexpectedStatus(status)
    }
  }

  private func baseQuery(for account: Account) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account.rawValue,
      kSecUseDataProtectionKeychain as String: usesDataProtectionKeychain
    ]
  }
}

extension Keychain {
  /// The account name of a Keychain item.
  public struct Account: RawRepresentable, Hashable, Sendable {
    /// The FlySto public-API token.
    public static let flyStoAPIToken = Self(rawValue: "flysto.api-token")

    /// The OpenSky Network OAuth client ID.
    public static let openSkyClientID = Self(rawValue: "opensky.client-id")

    /// The OpenSky Network OAuth client secret.
    public static let openSkyClientSecret = Self(rawValue: "opensky.client-secret")

    public let rawValue: String

    /// Creates an account name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }
  }
}

/// An error reading or writing the Keychain.
public enum KeychainError: Error, Equatable {
  /// A Keychain call failed.
  case unexpectedStatus(OSStatus)

  /// An item held data in an unexpected form.
  case unexpectedData
}

extension KeychainError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t access the Keychain.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case .unexpectedStatus(let status):
        let message = SecCopyErrorMessageString(status, nil) as String? ?? String(status)
        return String(localized: "The Keychain reported: \(message)", bundle: .module)
      case .unexpectedData:
        return String(localized: "A Keychain item contained unreadable data.", bundle: .module)
    }
  }
}
