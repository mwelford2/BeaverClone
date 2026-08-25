import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var config = APIConfig.shared

    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var isFetchingModels = false
    @State private var errorMessage: String?
    @State private var fetchSucceeded = false

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
                    SecureField("API Key", text: $apiKey)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("API Connection")
                } footer: {
                    Text("Works with any OpenAI-compatible endpoint (OpenAI, Azure OpenAI, local servers, etc.).")
                }

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

                if !config.models.isEmpty {
                    Section("Transcription Model") {
                        Picker("Transcription Model", selection: $config.transcriptionModel) {
                            Text("None").tag(String?.none)
                            ForEach(config.models, id: \.self) { model in
                                Text(model).tag(String?.some(model))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Section("Summarization Model") {
                        Picker("Summarization Model", selection: $config.chatModel) {
                            Text("None").tag(String?.none)
                            ForEach(config.models, id: \.self) { model in
                                Text(model).tag(String?.some(model))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }
            .formStyle(.grouped)
            .tint(BeaverTheme.accent)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty || baseURL.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .tint(BeaverTheme.accent)
    }

    private func load() {
        apiKey = config.apiKey
        baseURL = config.baseURL
    }

    private func save() {
        config.apiKey = apiKey
        config.baseURL = baseURL
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
            } catch {
                isFetchingModels = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
