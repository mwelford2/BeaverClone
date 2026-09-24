import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var config = APIConfig.shared

    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var isFetchingModels = false
    @State private var errorMessage: String?
    @State private var fetchSucceeded = false
    @State private var isEditingConnection = false
    @State private var isCheckingOnDeviceReadiness = false
    @State private var onDeviceReadinessError: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                if config.isOnDeviceTranscriptionAvailable {
                    Section {
                        Picker("Method", selection: transcriptionModeBinding) {
                            ForEach(APIConfig.TranscriptionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("transcriptionMethodPicker")
                    } header: {
                        Text("Transcription")
                    } footer: {
                        if config.transcriptionMode == .onDevice {
                            Text("Uses Apple's built-in speech recognition. Recorded audio stays on this device and transcription works without an internet connection.")
                                .accessibilityIdentifier("onDeviceDescription")
                            if isCheckingOnDeviceReadiness {
                                HStack(spacing: 6) {
                                    ProgressView()
                                    Text("Checking Speech Recognition…")
                                }
                            } else if let onDeviceReadinessError {
                                Text(onDeviceReadinessError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("onDeviceReadinessError")
                            }
                        } else {
                            Text("Short audio segments are sent to your configured transcription service.")
                        }
                    }
                }

                if config.transcriptionMode == .onDevice {
                    Section {
                        Picker("Language", selection: $config.onDeviceLocaleIdentifier) {
                            ForEach(config.availableOnDeviceLocales, id: \.identifier) { locale in
                                Text(localeDisplayName(locale)).tag(locale.identifier)
                            }
                        }
                        .accessibilityIdentifier("onDeviceLanguagePicker")
                    } header: {
                        Text("On-Device Settings")
                    } footer: {
                        Text("Choose the language spoken in recordings. Availability is determined by the speech models installed by the system.")
                    }
                }

                if config.transcriptionMode == .cloud {
                    Section {
                        TextField("Base URL", text: $baseURL)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .autocorrectionDisabled()
                            .disabled(!isEditingConnection)
                            .foregroundStyle(isEditingConnection ? .primary : .secondary)
                        SecureField("API Key", text: $apiKey)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .disabled(!isEditingConnection)
                            .foregroundStyle(isEditingConnection ? .primary : .secondary)
                    } header: {
                        Text("API Connection")
                    } footer: {
                        if isEditingConnection {
                            Text("Works with any OpenAI-compatible endpoint (OpenAI, Azure OpenAI, local servers, etc.).")
                        } else if config.apiKeySaveFailed {
                            Label("Couldn't save the API key to Keychain — try again", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else if config.isConfigured {
                            Label("Saved to Keychain — persists across restarts", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if isEditingConnection {
                        Section {
                            Button(action: fetchModels) {
                                HStack {
                                    Text("Fetch Available Models")
                                    Spacer()
                                    if isFetchingModels {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(apiKey.isEmpty || baseURL.isEmpty || isFetchingModels)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if fetchSucceeded {
                                Label("Connected — \(config.models.count) models found", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    } else {
                        Section {
                            Button("Edit Connection") { isEditingConnection = true }
                        }
                    }
                }

                #if os(iOS)
                Section {
                    Toggle("Keep Screen Awake", isOn: $config.keepScreenAwake)
                } footer: {
                    Text("Prevents your device from auto-locking while the app is open.")
                }
                #endif

                if config.transcriptionMode == .cloud && !config.models.isEmpty {
                    Section {
                        Picker("Transcription Model", selection: $config.transcriptionModel) {
                            Text("None").tag(String?.none)
                            ForEach(config.models, id: \.self) { model in
                                Text(model).tag(String?.some(model))
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Transcription Model")
                    } footer: {
                        savedFooter
                    }

                    Section {
                        Picker("Summarization Model", selection: $config.chatModel) {
                            Text("None").tag(String?.none)
                            ForEach(config.models, id: \.self) { model in
                                Text(model).tag(String?.some(model))
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Summarization Model")
                    } footer: {
                        savedFooter
                    }
                }

                if !config.isOnDeviceTranscriptionAvailable && !config.hideOnDeviceUnavailableNotice {
                    Section {
                        Text("On-device transcription isn't available for this device or language. Cloud transcription will continue to work normally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("onDeviceUnavailableNote")
                        Button("Hide This Note") {
                            config.hideOnDeviceUnavailableNotice = true
                        }
                        .font(.caption)
                        .accessibilityIdentifier("hideOnDeviceUnavailableNote")
                    }
                }
            }
            .formStyle(.grouped)
            .tint(BeaverTheme.accent)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingConnection ? "Save" : "Done") {
                        if isEditingConnection {
                            save()
                        }
                        dismiss()
                    }
                    .disabled(isEditingConnection && config.transcriptionMode == .cloud && (apiKey.isEmpty || baseURL.isEmpty))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .tint(BeaverTheme.accent)
    }

    private var savedFooter: some View {
        Label("Saved — selection persists across restarts", systemImage: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.green)
    }

    private var transcriptionModeBinding: Binding<APIConfig.TranscriptionMode> {
        Binding(
            get: { config.transcriptionMode },
            set: { mode in
                config.transcriptionMode = mode
                guard mode == .onDevice else {
                    isCheckingOnDeviceReadiness = false
                    onDeviceReadinessError = nil
                    return
                }
                validateOnDeviceReadiness()
            }
        )
    }

    private func load() {
        apiKey = config.apiKey
        baseURL = config.baseURL
        if !config.isOnDeviceTranscriptionAvailable && config.transcriptionMode == .onDevice {
            config.transcriptionMode = .cloud
        }
        if config.isOnDeviceTranscriptionAvailable,
           !config.availableOnDeviceLocales.contains(where: { $0.identifier == config.onDeviceLocaleIdentifier }) {
            config.onDeviceLocaleIdentifier = config.selectedOnDeviceLocale.identifier
        }
        // Only drop into edit mode if there's nothing saved yet.
        isEditingConnection = !config.isConfigured && config.transcriptionMode == .cloud
    }

    private func localeDisplayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private func save() {
        config.apiKey = apiKey
        config.baseURL = baseURL
        isEditingConnection = config.apiKeySaveFailed
    }

    private func fetchModels() {
        // Persist immediately so fetchModels() reads the values currently in the form.
        config.apiKey = apiKey
        config.baseURL = baseURL

        isFetchingModels = true
        errorMessage = nil
        fetchSucceeded = false

        Task {
            do {
                try await config.fetchModels()
                isFetchingModels = false
                fetchSucceeded = true
                isEditingConnection = config.apiKeySaveFailed
            } catch {
                isFetchingModels = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// On-device speech requires a system language model and the user's Speech Recognition
    /// permission. Check at selection time so a missing capability is explained in Settings,
    /// rather than only when the user tries to record.
    private func validateOnDeviceReadiness() {
        isCheckingOnDeviceReadiness = true
        onDeviceReadinessError = nil

        Task {
            do {
                try await OnDeviceTranscriptionService.shared.prepare()
                isCheckingOnDeviceReadiness = false
            } catch {
                isCheckingOnDeviceReadiness = false
                onDeviceReadinessError = error.localizedDescription
            }
        }
    }
}
