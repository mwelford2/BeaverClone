import Foundation
import Combine

@MainActor
public final class APIConfig: ObservableObject {
    public static let shared = APIConfig()

    private init() {
        apiKey = KeychainStore.shared.read(key: Keys.apiKey) ?? ""
        baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        transcriptionModel = UserDefaults.standard.string(forKey: Keys.transcriptionModel)
        chatModel = UserDefaults.standard.string(forKey: Keys.chatModel)
    }

    private enum Keys {
        static let apiKey = "apiKey"
        static let baseURL = "baseURL"
        static let transcriptionModel = "transcriptionModel"
        static let chatModel = "chatModel"
    }

    @Published public var apiKey: String {
        didSet { KeychainStore.shared.write(key: Keys.apiKey, value: apiKey) }
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
