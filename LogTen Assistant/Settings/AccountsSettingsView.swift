import Credentials
import SwiftUI

/// Settings ▸ Accounts: whether the FlySto token and the OpenSky client are set up, with the
/// sheet that edits each one. The credentials are kept in the Keychain.
struct AccountsSettingsView: View {
  @State private var model: AccountsModel
  @State private var editedService: AccountsModel.Service?

  var body: some View {
    Form {
      ForEach(AccountsModel.Service.allCases) { service in
        AccountSection(model: model, service: service) { editedService = service }
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { model.load() }
    .sheet(item: $editedService) { service in
      AccountCredentialsSheet(model: model, service: service)
    }
  }

  /// Creates the pane for credentials kept by a model.
  init(model: AccountsModel = AccountsModel()) {
    _model = State(initialValue: model)
  }
}

/// One service: whether its credentials are set up, the button that edits them, and what the
/// last save or test failed on.
private struct AccountSection: View {
  let model: AccountsModel
  let service: AccountsModel.Service
  let edit: () -> Void

  var body: some View {
    Section(service.title) {
      LabeledContent(service.credentialTitle) {
        HStack {
          AccountStateText(isConfigured: model.isConfigured(service), status: model.status[service])
            .fixedSize()
          Button(model.isConfigured(service) ? "Change…" : "Set Up…", action: edit)
            .accessibilityIdentifier("\(service.identifierPrefix).setUp")
        }
      }
      if case .failed(let message) = model.status[service] {
        Text(message)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
    }
  }
}

/// Whether a service is set up, or connected once a test has passed.
private struct AccountStateText: View {
  let isConfigured: Bool
  let status: AccountsModel.ConnectionStatus?

  var body: some View {
    Group {
      switch status {
        case .testing:
          ProgressView().controlSize(.small)
        case .connected:
          Text("Connected")
        default:
          if isConfigured {
            Text("Saved in Keychain")
          } else {
            Text("Not set up")
          }
      }
    }
    .foregroundStyle(.secondary)
  }
}

extension AccountsModel.Service: Identifiable {
  var id: Self { self }

  /// The service's name.
  var title: String {
    switch self {
      case .flySto: String(localized: "FlySto")
      case .openSky: String(localized: "OpenSky Network")
    }
  }

  /// What the service's credentials are called.
  var credentialTitle: String {
    switch self {
      case .flySto: String(localized: "API Token")
      case .openSky: String(localized: "API Client")
    }
  }

  /// The prefix of the accessibility identifiers of the service's controls.
  var identifierPrefix: String {
    switch self {
      case .flySto: "settings.flySto"
      case .openSky: "settings.openSky"
    }
  }
}

#Preview("Not Set Up") {
  SettingsPanePreview {
    AccountsSettingsView(model: AccountsModel(secrets: InMemorySecretStore()))
  }
}

#Preview("Set Up") {
  SettingsPanePreview {
    AccountsSettingsView(
      model: AccountsModel(
        secrets: InMemorySecretStore([
          .flyStoAPIToken: "token",
          .openSkyClientID: "pilot-api-client",
          .openSkyClientSecret: "secret"
        ])
      )
    )
  }
}
