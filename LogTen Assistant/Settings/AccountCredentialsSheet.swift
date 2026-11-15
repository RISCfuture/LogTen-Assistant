import Credentials
import SwiftUI

/**
 The sheet that edits one service's credentials: where to get them, the fields they go in, and
 Test and Save.

 Saving empty fields removes the service's credentials from the Keychain. Cancelling puts back
 the stored credentials.
 */
struct AccountCredentialsSheet: View {
  private static let width: CGFloat = 440
  private static let spacingBetweenGroups: CGFloat = 16

  @Bindable var model: AccountsModel
  let service: AccountsModel.Service

  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: Self.spacingBetweenGroups) {
      Text(service.sheetTitle)
        .font(.headline)
      CredentialInstructions(service: service)
      CredentialFields(model: model, service: service)
      if case .failed(let message) = model.status[service] {
        CredentialFailureView(message: message)
      }
      CredentialActions(
        status: model.status[service],
        canTest: model.canTest(service),
        identifierPrefix: service.identifierPrefix,
        cancel: cancel,
        test: test,
        save: save
      )
    }
    .padding()
    .frame(width: Self.width)
  }

  private func cancel() {
    model.discardChanges(to: service)
    dismiss()
  }

  private func test() {
    Task { await model.testConnection(to: service) }
  }

  private func save() {
    model.save(service)
    if model.status[service] == .saved { dismiss() }
  }
}

/// Where the service issues credentials, and the link that opens it.
private struct CredentialInstructions: View {
  let service: AccountsModel.Service

  var body: some View {
    VStack(alignment: .leading) {
      Text(service.instructions)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let url = service.accountURL {
        Link(service.accountLinkTitle, destination: url)
      }
    }
  }
}

/// The service's credential fields, labelled in a column.
private struct CredentialFields: View {
  @Bindable var model: AccountsModel
  let service: AccountsModel.Service

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline) {
      switch service {
        case .flySto:
          CredentialFieldRow(
            title: "API Token:",
            text: $model.flyStoToken,
            isSecret: true,
            identifier: "settings.flyStoToken"
          )
        case .openSky:
          CredentialFieldRow(
            title: "Client ID:",
            text: $model.openSkyClientID,
            isSecret: false,
            identifier: "settings.openSkyClientID"
          )
          CredentialFieldRow(
            title: "Client Secret:",
            text: $model.openSkyClientSecret,
            isSecret: true,
            identifier: "settings.openSkyClientSecret"
          )
      }
    }
  }
}

/**
 One labelled credential field.

 Monospaced, because a credential is checked one character at a time: someone comparing a
 pasted client ID with the one the service shows needs `l` and `1` to look different.
 */
private struct CredentialFieldRow: View {
  let title: LocalizedStringKey
  @Binding var text: String
  let isSecret: Bool
  let identifier: String

  var body: some View {
    GridRow {
      Text(title)
        .gridColumnAlignment(.trailing)
      Group {
        if isSecret {
          SecureField(title, text: $text, prompt: Text("Required"))
        } else {
          TextField(title, text: $text, prompt: Text("Required"))
        }
      }
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .monospaced()
      .accessibilityIdentifier(identifier)
    }
  }
}

/// What the last save or test failed on.
private struct CredentialFailureView: View {
  let message: String

  var body: some View {
    Label {
      Text(message)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    } icon: {
      Image(systemName: "exclamationmark.octagon.fill")
        .accessibilityHidden(true)
    }
    .foregroundStyle(.red)
  }
}

/// The sheet's buttons, with a test's progress or result at the leading end.
private struct CredentialActions: View {
  let status: AccountsModel.ConnectionStatus?
  let canTest: Bool
  let identifierPrefix: String
  let cancel: () -> Void
  let test: () -> Void
  let save: () -> Void

  var body: some View {
    HStack {
      CredentialTestResult(status: status)
      Spacer()
      Button("Cancel", role: .cancel, action: cancel)
        .keyboardShortcut(.cancelAction)
      Button("Test", action: test)
        .disabled(!canTest)
        .accessibilityIdentifier("\(identifierPrefix).test")
      Button("Save", action: save)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("\(identifierPrefix).save")
    }
  }
}

/// A test in progress, or one that passed.
private struct CredentialTestResult: View {
  let status: AccountsModel.ConnectionStatus?

  var body: some View {
    switch status {
      case .testing:
        HStack {
          Text("Testing…")
          ProgressView().controlSize(.small)
        }
        .foregroundStyle(.secondary)
      case .connected:
        Label {
          Text("Connected")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      default:
        EmptyView()
    }
  }
}

extension AccountsModel.Service {
  fileprivate var sheetTitle: String {
    switch self {
      case .flySto: String(localized: "FlySto API Token")
      case .openSky: String(localized: "OpenSky Network API Client")
    }
  }

  fileprivate var instructions: String {
    switch self {
      case .flySto:
        String(localized: "Create an API token in your FlySto account, then paste it here.")
      case .openSky:
        String(
          localized:
            "Create an API client in your OpenSky account, then paste its client ID and secret here."
        )
    }
  }

  fileprivate var accountLinkTitle: String {
    switch self {
      case .flySto: String(localized: "Open FlySto Account Settings")
      case .openSky: String(localized: "Open OpenSky Account")
    }
  }

  fileprivate var accountURL: URL? {
    switch self {
      case .flySto: URL(string: "https://www.flysto.net/account/api")
      case .openSky: URL(string: "https://opensky-network.org/my-opensky")
    }
  }
}

#Preview("FlySto") {
  AccountCredentialsSheet(
    model: AccountsModel(secrets: InMemorySecretStore()),
    service: .flySto
  )
}

#Preview("OpenSky") {
  let model = AccountsModel(secrets: InMemorySecretStore([.openSkyClientID: "pilot-api-client"]))
  model.load()
  return AccountCredentialsSheet(model: model, service: .openSky)
}

#Preview("Test Failed") {
  let model = AccountsModel(secrets: InMemorySecretStore([.flyStoAPIToken: "token"]))
  model.load()
  model.showForPreview(
    .failed("Couldn’t reach FlySto. FlySto rejected the API token."),
    for: .flySto
  )
  return AccountCredentialsSheet(model: model, service: .flySto)
}

#Preview("Test Passed") {
  let model = AccountsModel(secrets: InMemorySecretStore([.flyStoAPIToken: "token"]))
  model.load()
  model.showForPreview(.connected, for: .flySto)
  return AccountCredentialsSheet(model: model, service: .flySto)
}
