import Credentials
import FlightSources
import Foundation
import Observation

/// Where account secrets are kept: the Keychain in the app, memory in previews.
protocol SecretStore: Sendable {
  func string(for account: Keychain.Account) throws -> String?
  func set(_ string: String, for account: Keychain.Account) throws
  func remove(_ account: Keychain.Account) throws
}

extension Keychain: SecretStore {}

/// The FlySto and OpenSky credentials being edited in Settings ▸ Accounts.
@Observable
final class AccountsModel {
  /// The FlySto API token.
  var flyStoToken = ""

  /// The OpenSky OAuth client ID.
  var openSkyClientID = ""

  /// The OpenSky OAuth client secret.
  var openSkyClientSecret = ""

  /// The result of the last save or connection test for each service.
  private(set) var status = [Service: ConnectionStatus]()

  @ObservationIgnored private let secrets: any SecretStore

  /// Creates a model that keeps credentials in a store.
  init(secrets: any SecretStore = Keychain()) {
    self.secrets = secrets
  }

  private static func message(for error: any Error) -> String {
    let reason = (error as? any LocalizedError)?.failureReason
    return [error.localizedDescription, reason].compactMap(\.self).joined(separator: " ")
  }

  /// Reads the stored credentials into the fields.
  func load() {
    do {
      flyStoToken = try secrets.string(for: .flyStoAPIToken) ?? ""
      openSkyClientID = try secrets.string(for: .openSkyClientID) ?? ""
      openSkyClientSecret = try secrets.string(for: .openSkyClientSecret) ?? ""
    } catch {
      status[.flySto] = .failed(Self.message(for: error))
    }
  }

  /// Stores or removes a service's credentials to match the fields.
  func save(_ service: Service) {
    do {
      for (account, value) in fields(for: service) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          try secrets.remove(account)
        } else {
          try secrets.set(trimmed, for: account)
        }
      }
      status[service] = .saved
    } catch {
      status[service] = .failed(Self.message(for: error))
    }
  }

  /// Checks that the service accepts the credentials in the fields.
  func testConnection(to service: Service) async {
    status[service] = .testing
    do {
      switch service {
        case .flySto:
          let token = flyStoToken.trimmingCharacters(in: .whitespacesAndNewlines)
          _ = try await FlyStoClient(token: { token }).crew()
        case .openSky:
          let credentials = OpenSkyClient.Credentials(
            id: openSkyClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: openSkyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          try await OpenSkyClient(credentials: { credentials }).testConnection()
      }
      status[service] = .connected
    } catch {
      status[service] = .failed(Self.message(for: error))
    }
  }

  /// Puts back a service's stored credentials and forgets the result of testing the edits.
  func discardChanges(to service: Service) {
    load()
    status[service] = nil
  }

  /// Shows a status for a service as a save or connection test would, for previews.
  func showForPreview(_ status: ConnectionStatus, for service: Service) {
    self.status[service] = status
  }

  /// Whether the fields hold enough to test a service.
  func canTest(_ service: Service) -> Bool {
    status[service] != .testing && isConfigured(service)
  }

  /// Whether every credential the service needs is filled in.
  func isConfigured(_ service: Service) -> Bool {
    fields(for: service).allSatisfy { !$0.1.isEmpty }
  }

  private func fields(for service: Service) -> [(Keychain.Account, String)] {
    switch service {
      case .flySto: [(.flyStoAPIToken, flyStoToken)]
      case .openSky:
        [(.openSkyClientID, openSkyClientID), (.openSkyClientSecret, openSkyClientSecret)]
    }
  }

  /// A service whose credentials the app stores.
  enum Service: CaseIterable {
    case flySto
    case openSky
  }

  /// The result of saving or testing a service's credentials.
  enum ConnectionStatus: Equatable {
    case saved
    case testing
    case connected
    case failed(String)
  }
}

/// Secrets kept in memory, for previews.
final class InMemorySecretStore: SecretStore {
  private let values: [String: String]

  init(_ values: [Keychain.Account: String] = [:]) {
    self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
  }

  func string(for account: Keychain.Account) -> String? { values[account.rawValue] }

  func set(_: String, for _: Keychain.Account) {}

  func remove(_: Keychain.Account) {}
}
