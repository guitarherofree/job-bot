import Foundation
import JobBotCore

/// The optional AI writing service (Anthropic's Claude API). Used only when turned on in
/// Settings, with a key the person provides; every request is disclosed first.
struct AIClient {
    static let serviceName = "Anthropic (Claude API)"
    static let host = "api.anthropic.com"

    let apiKey: String
    let model: String

    enum AIError: Error, LocalizedError {
        case noKey
        case http(Int, String)
        case badReply
        case offline(String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "Add an Anthropic API key in Settings › AI to use AI drafting."
            case .http(401, _): return "Anthropic didn't accept the API key. Check it in Settings › AI."
            case .http(429, _): return "Anthropic says too many requests were sent. Wait a minute and try again."
            case .http(529, _), .http(503, _): return "Anthropic's service is busy. Try again in a few minutes."
            case .http(let code, let message): return "The AI request failed (\(code)): \(message)"
            case .badReply: return "The AI service sent a reply Job Bot couldn't read. Nothing was changed."
            case .offline(let why): return "Couldn't reach the AI service: \(why)"
            }
        }
    }

    func send(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIError.noKey }
        var request = URLRequest(url: URL(string: "https://\(Self.host)/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.offline(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let message = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: code)
            throw AIError.http(code, message)
        }
        guard let content = obj?["content"] as? [[String: Any]] else { throw AIError.badReply }
        let text = content.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined(separator: "\n")
        guard !text.isEmpty else { throw AIError.badReply }
        return text
    }
}
