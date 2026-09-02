import Foundation

public enum OpenAIServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case requestFailed(status: Int, body: String?)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configure your API key and base URL in Settings first."
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

public final class OpenAIService {
    public static let shared = OpenAIService()

    private init() {}

    @MainActor
    public func transcribeAudio(fileURL: URL) async throws -> (text: String, wordTimings: [WordTiming]) {
        try await transcribe(fileURL: fileURL)
    }

    /// Transcribes a single audio file — used both for the whole recording and, for live
    /// transcription, for one short segment at a time. Word timings returned are relative to
    /// the start of `fileURL` itself; callers stitching segments together must offset them.
    @MainActor
    public func transcribe(fileURL: URL) async throws -> (text: String, wordTimings: [WordTiming]) {
        let apiKey = APIConfig.shared.apiKey
        let model = APIConfig.shared.transcriptionModel ?? "whisper-1"

        guard APIConfig.shared.isConfigured else {
            throw OpenAIServiceError.notConfigured
        }
        guard let url = APIConfig.shared.normalizedURL(path: "audio/transcriptions") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let audioData = try Data(contentsOf: fileURL)
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        appendField("model", model)
        // Ask for word-level timestamps so playback can highlight the transcript in sync.
        // Not every OpenAI-compatible endpoint honors these fields — fall back to plain text below.
        appendField("response_format", "verbose_json")
        appendField("timestamp_granularities[]", "word")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenAIServiceError.requestFailed(status: status, body: String(data: data, encoding: .utf8))
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            var timings: [WordTiming] = []
            if let words = json["words"] as? [[String: Any]] {
                timings = words.compactMap { w in
                    guard let word = w["word"] as? String,
                          let start = w["start"] as? Double,
                          let end = w["end"] as? Double else { return nil }
                    return WordTiming(word: word, start: start, end: end)
                }
            }
            return (text, timings)
        }

        throw OpenAIServiceError.invalidData
    }

    @MainActor
    public func summarize(transcript: String) async throws -> (summary: String, title: String) {
        let apiKey = APIConfig.shared.apiKey
        let model = APIConfig.shared.chatModel ?? "gpt-3.5-turbo"

        guard APIConfig.shared.isConfigured else {
            throw OpenAIServiceError.notConfigured
        }
        guard let url = APIConfig.shared.normalizedURL(path: "chat/completions") else {
            throw OpenAIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You summarize meeting and voice-memo transcripts. Respond with exactly two sections:
        TITLE: a short 3-8 word title for this note
        SUMMARY: a concise summary with key points and action items as a bulleted list
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": "Transcript:\n\(transcript)"]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.4
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenAIServiceError.requestFailed(status: status, body: String(data: data, encoding: .utf8))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIServiceError.invalidData
        }

        return Self.parseTitleAndSummary(from: content)
    }

    static func parseTitleAndSummary(from content: String) -> (summary: String, title: String) {
        var title = ""
        var summaryLines: [String] = []
        var inSummary = false

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let rest = Self.stripLabel("TITLE", from: trimmed) {
                title = rest
                inSummary = false
            } else if let rest = Self.stripLabel("SUMMARY", from: trimmed) {
                if !rest.isEmpty { summaryLines.append(rest) }
                inSummary = true
            } else if inSummary {
                summaryLines.append(String(line))
            }
        }

        let summary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (summary.isEmpty ? content : summary, title)
    }

    /// Matches a line like "TITLE: foo" while tolerating the formatting variance models
    /// commonly produce despite being asked for a plain "LABEL:" prefix — markdown bold/heading
    /// markers, list bullets/numbering, and a colon/dash/space separator instead of just ":".
    /// Returns the trimmed remainder after the label if `line` starts with `label` (after
    /// stripping that decoration), or nil if it doesn't match at all.
    private static func stripLabel(_ label: String, from line: String) -> String? {
        var remaining = Substring(line)

        // Strip leading list markers: "-", "*", "1.", "1)".
        while let first = remaining.first, first == "-" || first == "*" || first == "#" {
            remaining = remaining.dropFirst()
        }
        remaining = remaining.drop { $0.isWhitespace }
        if let dotIndex = remaining.firstIndex(where: { $0 == "." || $0 == ")" }),
           remaining[remaining.startIndex..<dotIndex].allSatisfy({ $0.isNumber }),
           remaining.startIndex != dotIndex {
            remaining = remaining[remaining.index(after: dotIndex)...]
        }
        remaining = remaining.drop { $0.isWhitespace }

        // Strip markdown emphasis wrapping the label itself, e.g. "**TITLE:**" or "__TITLE__".
        for marker in ["**", "__"] {
            if remaining.hasPrefix(marker) {
                remaining = remaining.dropFirst(marker.count)
            }
        }

        guard remaining.uppercased().hasPrefix(label.uppercased()) else { return nil }
        remaining = remaining.dropFirst(label.count)

        // Allow closing emphasis markers right after the label: "TITLE**:" or "TITLE:**".
        for marker in ["**", "__"] {
            if remaining.hasPrefix(marker) {
                remaining = remaining.dropFirst(marker.count)
            }
        }

        remaining = remaining.drop { $0.isWhitespace }
        guard let separator = remaining.first, separator == ":" || separator == "-" || separator == "\u{2014}" else {
            return nil
        }
        remaining = remaining.dropFirst()

        for marker in ["**", "__"] {
            if remaining.hasPrefix(marker) {
                remaining = remaining.dropFirst(marker.count)
            }
        }

        var result = remaining.trimmingCharacters(in: .whitespaces)
        for marker in ["**", "__"] {
            if result.hasSuffix(marker) {
                result = String(result.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
}
