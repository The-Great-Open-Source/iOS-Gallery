import SwiftUI
import SwiftData

struct BackupSettingsView: View {
    @EnvironmentObject private var engine: BackupEngine
    @ObservedObject private var drive = GoogleDriveService.shared
    @AppStorage(BackupSettings.Key.maxFileSizeMB) private var maxMB = BackupSettings.defaultMaxFileSizeMB
    @AppStorage(BackupSettings.Key.includePhotos) private var includePhotos = true
    @AppStorage(BackupSettings.Key.includeVideos) private var includeVideos = true
    @AppStorage(BackupSettings.Key.wifiOnly) private var wifiOnly = true
    @AppStorage(BackupSettings.Key.driveAuto) private var driveAuto = false
    @AppStorage(BackupSettings.Key.telegramBotName) private var botName = ""
    @State private var telegramConnected = TelegramService.isConfigured
    @State private var errorMessage: String?
    @State private var signingIn = false

    private let sizes = [10, 25, 50, 100, 250, 500, 1000, 2000]

    var body: some View {
        Form {
            Section {
                Picker("Maximum file size", selection: $maxMB) {
                    ForEach(sizes, id: \.self) { Text($0 >= 1000 ? "\($0 / 1000) GB" : "\($0) MB").tag($0) }
                }
                Toggle("Photos", isOn: $includePhotos)
                Toggle("Videos", isOn: $includeVideos)
                Toggle("Wi-Fi only (automatic backup)", isOn: $wifiOnly)
            } header: { Text("Limits") } footer: {
                Text("Files larger than the maximum are skipped. Telegram bots accept up to 50 MB per file, so the lower limit applies there.")
            }

            Section {
                if !GoogleDriveConfig.isConfigured {
                    Text("Google Drive isn't set up in this build. Add your OAuth client ID in GoogleDriveConfig.swift.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if drive.isSignedIn {
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Toggle("Automatic backup", isOn: $driveAuto)
                    if driveAuto {
                        NavigationLink("Collections to Back Up") { AutoBackupCollectionsView() }
                        Button("Back Up Now") { Task { await engine.runAutomatic() } }
                            .disabled(engine.isRunning)
                        if engine.isRunning {
                            ProgressView(value: engine.progress) { Text("Uploading \(engine.processed) of \(engine.total)").font(.footnote) }
                        }
                    }
                    Button("Sign Out", role: .destructive) { drive.signOut(); driveAuto = false }
                } else {
                    Button { signIn() } label: {
                        HStack { Text("Sign In with Google"); if signingIn { Spacer(); ProgressView() } }
                    }.disabled(signingIn)
                }
            } header: { Text("Google Drive") } footer: {
                if drive.isSignedIn && driveAuto {
                    Text("New items in the selected collections are uploaded when iOS allows it: while the app is open and during background windows. Each file is uploaded once.")
                } else {
                    Text("Backs up to a “Good Gallery Backup” folder in your Drive, with a subfolder per collection. Good Gallery can only see files it created.")
                }
            }
            .listRowSeparator(.visible)

            Section {
                NavigationLink {
                    TelegramSetupView { telegramConnected = TelegramService.isConfigured }
                } label: {
                    HStack {
                        Text("Telegram")
                        Spacer()
                        Text(telegramConnected ? (botName.isEmpty ? "Connected" : "@\(botName)") : "Not Set Up").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Telegram") } footer: {
                Text("Send a collection to your own Telegram chat using your own bot. Manual only.")
            }
        }
        .tint(GG.Palette.accent)
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't Sign In", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .onAppear { telegramConnected = TelegramService.isConfigured }
    }

    private func signIn() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do { try await drive.signIn() }
            catch DriveError.cancelled {}
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct AutoBackupCollectionsView: View {
    @EnvironmentObject private var store: CollectionStore
    @Query(sort: \MediaCollection.sortOrder) private var collections: [MediaCollection]

    var body: some View {
        List {
            if collections.isEmpty {
                Text("Create a collection first.").foregroundStyle(.secondary)
            }
            ForEach(collections) { collection in
                Toggle(isOn: Binding(get: { collection.autoBackupDrive },
                                     set: { collection.autoBackupDrive = $0; try? store.context.save() })) {
                    VStack(alignment: .leading) {
                        Text(collection.name)
                        Text(Format.count(collection.items.count)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(GG.Palette.accent)
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TelegramSetupView: View {
    var onChange: () -> Void = {}
    @AppStorage(BackupSettings.Key.telegramChatID) private var chatID = ""
    @AppStorage(BackupSettings.Key.telegramBotName) private var botName = ""
    @State private var token = ""
    @State private var chatTitle = ""
    @State private var busy = false
    @State private var message: String?
    @State private var verified = TelegramService.token != nil

    var body: some View {
        Form {
            Section {
                Text("1. In Telegram, open @BotFather and send /newbot.\n2. Copy the token it gives you and paste it below.")
                    .font(.footnote)
                SecureField("Bot token", text: $token).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button(verified ? "Verify Again" : "Verify Token") { verify() }.disabled(token.isEmpty || busy)
                if verified, !botName.isEmpty { Label("@\(botName)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            } header: { Text("Your Bot") }

            if verified {
                Section {
                    Text("Open your bot in Telegram and send it any message (or add it to a private channel as admin and post there). Then tap Detect Chat.")
                        .font(.footnote)
                    Button("Detect Chat") { detect() }.disabled(busy)
                    TextField("Chat ID or @channelname", text: $chatID).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !chatTitle.isEmpty { Label(chatTitle, systemImage: "bubble.left.fill").foregroundStyle(.secondary) }
                } header: { Text("Destination") }
            }

            if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }

            if TelegramService.token != nil {
                Section { Button("Disconnect Telegram", role: .destructive) { disconnect() } }
            }
        }
        .tint(GG.Palette.accent)
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView() } }
        .onDisappear { onChange() }
    }

    private func verify() {
        busy = true; message = nil
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            do {
                botName = try await TelegramService.verify(token: value)
                Keychain.set(value, for: TelegramService.tokenKey)
                token = ""
                verified = true
                message = "Token verified."
            } catch { message = error.localizedDescription; verified = false }
        }
    }

    private func detect() {
        guard let token = TelegramService.token else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let chat = try await TelegramService.detectChat(token: token)
                chatID = chat.id; chatTitle = chat.title
                message = "Connected to “\(chat.title)”."
            } catch { message = error.localizedDescription }
        }
    }

    private func disconnect() {
        TelegramService.disconnect()
        verified = false; token = ""; chatTitle = ""; message = nil
        onChange()
    }
}
