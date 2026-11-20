import Foundation
import JobBotCore

/// Downloads job pages the person points to, and listings from public job-board feeds.
/// It identifies itself honestly, sends no cookies or personal data, and stops (asking for the
/// text instead) when a site requires sign-in or blocks automated visitors.
enum WebFetcher {
    static let userAgent = "JobBot/1.0 (Macintosh; personal job search app)"

    enum FetchError: Error, LocalizedError {
        case notAllowed(String)
        case blocked(String)
        case boardBlocked(String)
        case notFound
        case http(Int)
        case offline(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notAllowed(let why): return why
            case .blocked(let host): return "\(host) didn't let Job Bot read this page (it requires sign-in or blocks automated visitors). Open it in your browser, copy the job description, and paste it instead."
            case .boardBlocked(let host): return "\(host) didn't let Job Bot read its job list. Open the careers page in your browser instead."
            case .notFound: return "The page wasn't found. The posting may have been removed."
            case .http(let code): return "The site answered with an error (\(code)). Try again later, or paste the description instead."
            case .offline(let why): return "Couldn't reach the site: \(why)"
            case .unreadable: return "The page didn't contain readable text. Paste the description instead."
            }
        }
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL, accept: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FetchError.unreadable }
            return (data, http)
        } catch let e as FetchError {
            throw e
        } catch {
            throw FetchError.offline(error.localizedDescription)
        }
    }

    /// Fetches a job page. Returns its HTML.
    static func jobPage(_ url: URL) async throws -> String {
        if let reason = FetchPolicy.blockedReason(for: url) { throw FetchError.notAllowed(reason) }
        let (data, http) = try await get(url, accept: "text/html,application/xhtml+xml")
        let host = url.host ?? "The site"
        switch http.statusCode {
        case 200..<300: break
        case 401, 403, 429: throw FetchError.blocked(host)
        case 404, 410: throw FetchError.notFound
        default: throw FetchError.http(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw FetchError.unreadable }
        return html
    }

    /// Fetches a public job-board feed.
    static func board(_ kind: BoardKind, token: String) async throws -> Data {
        guard let url = kind.listingURL(token: token) else { throw FetchError.unreadable }
        return try await board(BoardRequest(url: url))
    }

    /// Sends one job-board request (a list, a search, or one posting) and returns the JSON.
    static func board(_ request: BoardRequest) async throws -> Data {
        let url = request.url
        var r = URLRequest(url: url)
        r.httpMethod = request.method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, http) = try await send(r)
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw FetchError.notFound
        case 401, 403, 429: throw FetchError.boardBlocked(url.host ?? "The job board")
        default: throw FetchError.http(http.statusCode)
        }
    }
}
