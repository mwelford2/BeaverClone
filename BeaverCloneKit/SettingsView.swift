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

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
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
                    } else {
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

                if !config.models.isEmpty {
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
                    .disabled(isEditingConnection && (apiKey.isEmpty || baseURL.isEmpty))
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

    private func load() {
        apiKey = config.apiKey
        baseURL = config.baseURL
        // Only drop into edit mode if there's nothing saved yet.
        isEditingConnection = !config.isConfigured
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
}
