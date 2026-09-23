import Foundation
import Combine
import Speech
#if os(iOS)
import UIKit
#endif

@MainActor
public final class APIConfig: ObservableObject {
    public enum TranscriptionMode: String, CaseIterable, Identifiable {
        case cloud
        case onDevice

        public var id: String { rawValue }
        public var title: String { self == .cloud ? "Cloud" : "On Device" }
    }

    public static let shared = APIConfig()

    private init() {
        apiKey = KeychainStore.shared.read(key: Keys.apiKey) ?? ""
        baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        transcriptionModel = UserDefaults.standard.string(forKey: Keys.transcriptionModel)
        chatModel = UserDefaults.standard.string(forKey: Keys.chatModel)
        keepScreenAwake = UserDefaults.standard.bool(forKey: Keys.keepScreenAwake)
        transcriptionMode = TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: Keys.transcriptionMode) ?? "") ?? .cloud
        onDeviceLocaleIdentifier = UserDefaults.standard.string(forKey: Keys.onDeviceLocaleIdentifier) ?? Locale.current.identifier
        hideOnDeviceUnavailableNotice = UserDefaults.standard.bool(forKey: Keys.hideOnDeviceUnavailableNotice)
        availableOnDeviceLocales = Self.detectAvailableOnDeviceLocales()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        #endif
    }

    private enum Keys {
        static let apiKey = "apiKey"
        static let baseURL = "baseURL"
        static let transcriptionModel = "transcriptionModel"
        static let chatModel = "chatModel"
        static let keepScreenAwake = "keepScreenAwake"
        static let transcriptionMode = "transcriptionMode"
        static let onDeviceLocaleIdentifier = "onDeviceLocaleIdentifier"
        static let hideOnDeviceUnavailableNotice = "hideOnDeviceUnavailableNotice"
    }

    /// Set by the apiKey didSet whenever a write to the Keychain is attempted, so callers
    /// (Settings UI) can tell the user when persistence actually failed instead of assuming success.
    @Published public private(set) var apiKeySaveFailed = false

    @Published public var apiKey: String {
        didSet {
            let succeeded = KeychainStore.shared.write(key: Keys.apiKey, value: apiKey)
            apiKeySaveFailed = !succeeded && !apiKey.isEmpty
        }
    }

    @Published public var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
            if oldValue != baseURL {
                models = []
                transcriptionModel = nil
                chatModel = nil
            }
        }
    }

    @Published public var models: [String] = []

    @Published public var transcriptionModel: String? {
        didSet { UserDefaults.standard.set(transcriptionModel, forKey: Keys.transcriptionModel) }
    }

    @Published public var chatModel: String? {
        didSet { UserDefaults.standard.set(chatModel, forKey: Keys.chatModel) }
    }

    /// When true, prevents the device from auto-locking/sleeping while the app is in the
    /// foreground — useful for long recordings. iOS only; no-op on macOS, which doesn't
    /// sleep the display just because an app window is open.
    @Published public var keepScreenAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: Keys.keepScreenAwake)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            #endif
        }
    }

    @Published public var transcriptionMode: TranscriptionMode {
        didSet { UserDefaults.standard.set(transcriptionMode.rawValue, forKey: Keys.transcriptionMode) }
    }

    @Published public var onDeviceLocaleIdentifier: String {
        didSet { UserDefaults.standard.set(onDeviceLocaleIdentifier, forKey: Keys.onDeviceLocaleIdentifier) }
    }

    @Published public var hideOnDeviceUnavailableNotice: Bool {
        didSet { UserDefaults.standard.set(hideOnDeviceUnavailableNotice, forKey: Keys.hideOnDeviceUnavailableNotice) }
    }

    public let availableOnDeviceLocales: [Locale]

    public var isOnDeviceTranscriptionAvailable: Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ForceOnDeviceTranscriptionAvailable") { return true }
        if ProcessInfo.processInfo.arguments.contains("-ForceOnDeviceTranscriptionUnavailable") { return false }
        #endif
        return !availableOnDeviceLocales.isEmpty
    }

    private static func detectAvailableOnDeviceLocales() -> [Locale] {
        let locales = SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .sorted {
                let first = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let second = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
            }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ForceOnDeviceTranscriptionAvailable"), locales.isEmpty {
            return [.current]
        }
        #endif
        return locales
    }

    public var selectedOnDeviceLocale: Locale {
        let selected = availableOnDeviceLocales.first { $0.identifier == onDeviceLocaleIdentifier }
        let current = availableOnDeviceLocales.first { $0.identifier == Locale.current.identifier }
        return selected ?? current ?? availableOnDeviceLocales.first ?? .current
    }

    public var canTranscribe: Bool {
        (transcriptionMode == .onDevice && isOnDeviceTranscriptionAvailable) || isConfigured
    }

    public var isConfigured: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty
    }

    public func normalizedURL(path: String) -> URL? {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: "\(trimmedBase)/\(path)")
    }

    @discardableResult
    public func fetchModels() async throws -> [String] {
        guard isConfigured else {
            throw APIConfigError.notConfigured
        }
        guard let url = normalizedURL(path: "models") else {
            throw APIConfigError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIConfigError.requestFailed(status: status, body: String(data: data, encoding: .utf8))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw APIConfigError.invalidData
        }

        let modelIDs = dataArray.compactMap { $0["id"] as? String }.sorted()

        self.models = modelIDs
        if transcriptionModel == nil {
            transcriptionModel = modelIDs.first { $0.localizedCaseInsensitiveContains("whisper") || $0.localizedCaseInsensitiveContains("transcribe") } ?? modelIDs.first
        }
        if chatModel == nil {
            chatModel = modelIDs.first { $0.localizedCaseInsensitiveContains("gpt") || $0.localizedCaseInsensitiveContains("chat") } ?? modelIDs.first
        }
        return modelIDs
    }
}

public enum APIConfigError: LocalizedError {
    case notConfigured
    case invalidURL
    case requestFailed(status: Int, body: String?)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Enter an API key and base URL first."
        case .invalidURL:
            return "That base URL doesn't look valid."
        case .requestFailed(let status, let body):
            if let body, !body.isEmpty {
                return "Request failed (\(status)): \(body)"
            }
            return "Request failed with status \(status)."
        case .invalidData:
            return "The server response wasn't in the expected format."
        }
    }
}
