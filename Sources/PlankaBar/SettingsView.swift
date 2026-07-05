import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var data = PlankaData.shared

    @State private var username: String = (try? Keychain.read(key: Keychain.usernameKey)) ?? ""
    @State private var password: String = (try? Keychain.read(key: Keychain.passwordKey)) ?? ""
    @State private var loginStatus: LoginStatus = PlankaClient.shared.hasToken ? .loggedIn : .loggedOut
    @State private var statusMessage: String?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var busy = false

    enum LoginStatus { case loggedOut, working, loggedIn }

    var body: some View {
        Form {
            Section("Planka Server") {
                TextField("URL", text: $settings.serverURL, prompt: Text("https://planka.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                TextField("Email or username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(loginStatus == .loggedIn ? "Re-log In" : "Log In") {
                        Task { await logIn() }
                    }
                    .disabled(busy || settings.serverURL.isEmpty || username.isEmpty || password.isEmpty)

                    if loginStatus == .loggedIn {
                        Button("Log Out") { logOut() }.disabled(busy)
                    }

                    Spacer()

                    switch loginStatus {
                    case .loggedIn:
                        Label("Logged in", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .working:
                        ProgressView().controlSize(.small)
                    case .loggedOut:
                        Label("Not logged in", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Defaults for New Cards") {
                Picker("Project", selection: $settings.defaultProjectId) {
                    Text("None").tag("")
                    ForEach(data.projects) { Text($0.name).tag($0.id) }
                }
                .onChange(of: settings.defaultProjectId) { _ in
                    settings.defaultBoardId = firstBoardId() ?? ""
                }

                Picker("Board", selection: $settings.defaultBoardId) {
                    Text("None").tag("")
                    ForEach(data.boards(forProject: settings.defaultProjectId)) { Text($0.name).tag($0.id) }
                }
                .onChange(of: settings.defaultBoardId) { newValue in
                    settings.defaultListId = ""
                    settings.defaultLabelId = ""
                    guard !newValue.isEmpty else { return }
                    Task {
                        await data.refreshBoard(newValue)
                        if settings.defaultListId.isEmpty {
                            settings.defaultListId = data.lists(forBoard: newValue).first?.id ?? ""
                        }
                    }
                }

                Picker("List (column)", selection: $settings.defaultListId) {
                    Text("None").tag("")
                    ForEach(data.lists(forBoard: settings.defaultBoardId)) { Text($0.displayName).tag($0.id) }
                }

                Picker("Label", selection: $settings.defaultLabelId) {
                    Text("None").tag("")
                    ForEach(data.labels(forBoard: settings.defaultBoardId)) { Text($0.displayName).tag($0.id) }
                }

                Picker("New card position", selection: $settings.newCardsAtTop) {
                    Text("Top of list").tag(true)
                    Text("Bottom of list").tag(false)
                }

                HStack {
                    Button("Refresh from Planka") {
                        Task { await refreshAll() }
                    }
                    .disabled(busy || loginStatus != .loggedIn)
                    if data.isRefreshing { ProgressView().controlSize(.small) }
                }
            }

            Section("Shortcut & Startup") {
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    ShortcutRecorderView(keyCode: $settings.hotkeyKeyCode,
                                         modifiers: $settings.hotkeyModifiers) {
                        HotKeyManager.shared.registerFromSettings()
                        AppDelegate.shared?.rebuildMenu()
                    }
                    .frame(width: 210)
                }
                Toggle("Launch at startup", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if let error = LaunchAtLogin.set(enabled: newValue) {
                            statusMessage = error
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func firstBoardId() -> String? {
        data.boards(forProject: settings.defaultProjectId).first?.id
    }

    private func logIn() async {
        busy = true
        loginStatus = .working
        statusMessage = nil
        defer { busy = false }
        do {
            try await PlankaClient.shared.logIn(emailOrUsername: username, password: password)
            try Keychain.save(key: Keychain.usernameKey, value: username)
            try Keychain.save(key: Keychain.passwordKey, value: password)
            loginStatus = .loggedIn
            await refreshAll()
        } catch {
            loginStatus = .loggedOut
            statusMessage = error.localizedDescription
        }
    }

    private func logOut() {
        PlankaClient.shared.logOut()
        Keychain.delete(key: Keychain.passwordKey)
        loginStatus = .loggedOut
        statusMessage = nil
        data.clear()
        SettingsStore.shared.clearAll()
    }

    private func refreshAll() async {
        guard await data.refreshProjects() else {
            statusMessage = data.lastError
            return
        }
        statusMessage = nil
        // Fill in sensible defaults on first login.
        if settings.defaultProjectId.isEmpty || !data.projects.contains(where: { $0.id == settings.defaultProjectId }) {
            settings.defaultProjectId = data.projects.first?.id ?? ""
            settings.defaultBoardId = firstBoardId() ?? ""
        }
        if !settings.defaultBoardId.isEmpty {
            await data.refreshBoard(settings.defaultBoardId)
            if settings.defaultListId.isEmpty {
                settings.defaultListId = data.lists(forBoard: settings.defaultBoardId).first?.id ?? ""
            }
        }
    }
}
