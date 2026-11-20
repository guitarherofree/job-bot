import Foundation

// MARK: - Requests

/// One request to a public job board. Job Bot sends nothing about the person: only the board's
/// address and, for search-based boards, a search term.
public struct BoardRequest: Equatable {
    public var url: URL
    public var method: String
    public var body: Data?

    public init(url: URL, method: String = "GET", body: Data? = nil) {
        self.url = url
        self.method = method
        self.body = body
    }
}

/// A Workday careers site, stored as "host/site" (for example
/// "amplify.wd1.myworkdayjobs.com/Amplify_Careers"). The tenant is the first part of the host.
public struct WorkdaySite: Equatable {
    public var host: String
    public var tenant: String
    public var site: String

    public init?(token: String) {
        let parts = token.trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased().hasSuffix(".myworkdayjobs.com"),
              let tenant = parts[0].split(separator: ".").first else { return nil }
        host = parts[0].lowercased()
        self.tenant = String(tenant).lowercased()
        site = parts[parts.count - 1]
    }

    public var token: String { "\(host)/\(site)" }
    public var searchURL: URL? { URL(string: "https://\(host)/wday/cxs/\(tenant)/\(site)/jobs") }

    public func detailURL(externalPath: String) -> String {
        "https://\(host)/wday/cxs/\(tenant)/\(site)\(Self.path(externalPath))"
    }

    public func publicURL(externalPath: String) -> String {
        "https://\(host)/\(site)\(Self.path(externalPath))"
    }

    static func path(_ p: String) -> String {
        let withSlash = p.hasPrefix("/") ? p : "/" + p
        return withSlash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? withSlash
    }
}

extension BoardKind {
    /// The requests that list a board's open roles. Search-based boards (Workday) get one search
    /// per term; the others list everything in one request (more pages follow via `nextPage`).
    public func listingRequests(token: String, terms: [String]) -> [BoardRequest] {
        switch self {
        case .none:
            return []
        case .workday:
            guard let url = WorkdaySite(token: token)?.searchURL else { return [] }
            var seen = Set<String>()
            let searches = terms.map { $0.trimmed }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            return (searches.isEmpty ? [""] : searches).map { term in
                let body: [String: Any] = ["appliedFacets": [String: Any](), "limit": 20, "offset": 0, "searchText": term]
                return BoardRequest(url: url, method: "POST", body: try? JSONSerialization.data(withJSONObject: body))
            }
        default:
            return listingURL(token: token).map { [BoardRequest(url: $0)] } ?? []
        }
    }
}

// MARK: - Feeds added in 1.0.3

/// Parsers for SmartRecruiters, Workable and Workday. Each is defensive: a field that's missing
/// is left empty rather than failing the whole board.
enum ListingFeeds {
    static func parse(_ obj: Any, kind: BoardKind, company: String, token: String, now: Date) -> [DiscoveredJob] {
        switch kind {
        case .smartrecruiters: return smartRecruiters(obj, company: company, token: token)
        case .workable: return workable(obj, company: company, token: token)
        case .workday: return workday(obj, company: company, token: token, now: now)
        default: return []
        }
    }

    static func string(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmed }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func join(_ parts: [String]) -> String {
        var seen = Set<String>()
        return parts.map { $0.trimmed }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
    }

    // SmartRecruiters: {"totalFound": n, "content": [{"id", "name", "releasedDate", "company": {"name"},
    // "location": {"city", "region", "country", "remote", "fullLocation"}, "ref"}]}
    static func smartRecruiters(_ obj: Any, company: String, token: String) -> [DiscoveredJob] {
        guard let dict = obj as? [String: Any], let items = dict["content"] as? [[String: Any]] else { return [] }
        return items.compactMap { j in
            let id = string(j["id"])
            guard !id.isEmpty else { return nil }
            let loc = j["location"] as? [String: Any] ?? [:]
            let remote = (loc["remote"] as? Bool) ?? false
            var location = string(loc["fullLocation"])
            if location.isEmpty { location = join([string(loc["city"]), string(loc["region"]), string(loc["country"]).uppercased()]) }
            if remote && !location.lowercased().contains("remote") { location = location.isEmpty ? "Remote" : "Remote (\(location))" }
            let employer = string((j["company"] as? [String: Any])?["name"])
            let t = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
            var detail = string(j["ref"])
            if detail.isEmpty { detail = "https://api.smartrecruiters.com/v1/companies/\(t)/postings/\(id)" }
            return DiscoveredJob(id: "sr-\(id)", title: string(j["name"]), employer: employer.isEmpty ? company : employer,
                                 location: location, url: "https://jobs.smartrecruiters.com/\(t)/\(id)",
                                 source: "SmartRecruiters (\(company))", posted: HTMLText.parseDate(j["releasedDate"] as? String),
                                 descriptionHTML: "", remote: remote, detailURL: detail)
        }
    }

    // Workable widget feed: {"jobs": [{"title", "shortcode", "url", "shortlink", "published_on",
    // "telecommuting", "city", "state", "country", "locations": [...], "description"}]}
    static func workable(_ obj: Any, company: String, token: String) -> [DiscoveredJob] {
        guard let dict = obj as? [String: Any], let items = dict["jobs"] as? [[String: Any]] else { return [] }
        return items.compactMap { j in
            let code = string(j["shortcode"])
            guard !code.isEmpty else { return nil }
            let remote = (j["telecommuting"] as? Bool) ?? false
            var location = join([string(j["city"]), string(j["state"]), string(j["country"])])
            if location.isEmpty, let first = (j["locations"] as? [[String: Any]])?.first {
                location = join([string(first["city"]), string(first["region"]), string(first["country"])])
            }
            if remote && !location.lowercased().contains("remote") { location = location.isEmpty ? "Remote" : "Remote (\(location))" }
            var html = string(j["description"])
            for (key, heading) in [("requirements", "Requirements"), ("benefits", "Benefits")] {
                let part = string(j[key])
                if !part.isEmpty { html += "<h3>\(heading)</h3>" + part }
            }
            var url = string(j["url"])
            if url.isEmpty { url = string(j["shortlink"]) }
            if url.isEmpty { url = "https://apply.workable.com/\(token)/j/\(code)/" }
            let t = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
            let published = string(j["published_on"])
            let posted = HTMLText.parseDate(published.isEmpty ? string(j["created_at"]) : published)
            return DiscoveredJob(id: "wk-\(code)", title: string(j["title"]), employer: company, location: location, url: url,
                                 source: "Workable (\(company))", posted: posted,
                                 descriptionHTML: html, remote: remote,
                                 detailURL: html.isEmpty ? "https://apply.workable.com/api/v2/accounts/\(t)/jobs/\(code)" : nil)
        }
    }

    // Workday search: {"total": n, "jobPostings": [{"title", "externalPath", "locationsText", "postedOn"}]}
    static func workday(_ obj: Any, company: String, token: String, now: Date) -> [DiscoveredJob] {
        guard let dict = obj as? [String: Any], let items = dict["jobPostings"] as? [[String: Any]],
              let site = WorkdaySite(token: token) else { return [] }
        return items.compactMap { j in
            let path = string(j["externalPath"])
            guard !path.isEmpty else { return nil }
            var location = string(j["locationsText"])
            // "3 Locations" says nothing yet; the posting itself lists them.
            if location.range(of: #"^\d+ Locations?$"#, options: [.regularExpression, .caseInsensitive]) != nil { location = "" }
            return DiscoveredJob(id: "wd-\(site.tenant)-\(path)", title: string(j["title"]), employer: company, location: location,
                                 url: site.publicURL(externalPath: path), source: "Workday (\(company))",
                                 posted: relativePostedDate(string(j["postedOn"]), now: now), descriptionHTML: "",
                                 remote: location.lowercased().contains("remote"), detailURL: site.detailURL(externalPath: path))
        }
    }

    /// Workday says "Posted Today", "Posted Yesterday", "Posted 3 Days Ago", "Posted 30+ Days Ago".
    static func relativePostedDate(_ s: String, now: Date) -> Date? {
        let lower = s.lowercased()
        let day: TimeInterval = 86_400
        if lower.contains("today") { return now }
        if lower.contains("yesterday") { return now.addingTimeInterval(-day) }
        if let r = lower.range(of: #"\d+"#, options: .regularExpression), let n = Double(lower[r]), lower.contains("day") {
            return now.addingTimeInterval(-n * day)
        }
        return nil
    }

    // MARK: Full postings

    static func applyDetail(_ obj: Any, kind: BoardKind, to job: inout DiscoveredJob) {
        guard let dict = obj as? [String: Any] else { return }
        switch kind {
        case .smartrecruiters:
            let sections = (dict["jobAd"] as? [String: Any])?["sections"] as? [String: Any] ?? [:]
            var html = ""
            for key in ["jobDescription", "qualifications", "additionalInformation"] {
                guard let section = sections[key] as? [String: Any] else { continue }
                let text = string(section["text"])
                guard !text.isEmpty else { continue }
                let title = string(section["title"])
                html += (title.isEmpty ? "" : "<h3>\(title)</h3>") + text
            }
            job.descriptionHTML = html
            let url = string(dict["postingUrl"])
            if !url.isEmpty { job.url = url }
        case .workable:
            var html = string(dict["description"])
            for (key, heading) in [("requirements", "Requirements"), ("benefits", "Benefits")] {
                let part = string(dict[key])
                if !part.isEmpty { html += "<h3>\(heading)</h3>" + part }
            }
            job.descriptionHTML = html
        case .workday:
            let info = dict["jobPostingInfo"] as? [String: Any] ?? [:]
            job.descriptionHTML = string(info["jobDescription"])
            let more = (info["additionalLocations"] as? [Any])?.map { string($0) } ?? []
            let location = join([string(info["location"])] + more)
            if !location.isEmpty { job.location = location }
            let remoteType = string(info["remoteType"]).lowercased()
            if remoteType.contains("remote") || location.lowercased().contains("remote") { job.remote = true }
            if let start = HTMLText.parseDate(info["startDate"] as? String) { job.posted = start }
            let url = string(info["externalUrl"])
            if !url.isEmpty { job.url = url }
        default:
            break
        }
    }
}

extension Boards {
    /// The next page of a paged board, if the response says there's more (SmartRecruiters lists
    /// 100 at a time). Stops after 500 postings.
    public static func nextPage(after data: Data, request: BoardRequest, kind: BoardKind) -> BoardRequest? {
        guard kind == .smartrecruiters,
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let total = (dict["totalFound"] as? NSNumber)?.intValue,
              var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else { return nil }
        let current = parts.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0"
        let offset = Int(current) ?? 0
        let next = offset + 100
        guard next < total, next < 500 else { return nil }
        var items = (parts.queryItems ?? []).filter { $0.name != "offset" }
        items.append(URLQueryItem(name: "offset", value: String(next)))
        parts.queryItems = items
        return parts.url.map { BoardRequest(url: $0) }
    }

    /// Fills in a posting's description from its full page on the board.
    public static func applyDetail(_ data: Data, to job: inout DiscoveredJob) throws {
        let obj = try JSONSerialization.jsonObject(with: data)
        ListingFeeds.applyDetail(obj, kind: job.board, to: &job)
    }
}

// MARK: - Searching every connected board

public enum BoardSearch {
    public struct Outcome {
        public var jobs: [DiscoveredJob] = []
        public var notes: [String] = []
        /// Companies whose boards were read without an error.
        public var searched: Set<String> = []
        public var requests = 0
        public init() {}
    }

    /// Lists every connected board, keeps titles that match the search terms, reads the full
    /// posting where the list leaves it out, then keeps the chosen locations.
    public static func run(companies: [CompanySource], terms: [String], locations: LocationFilter, detailLimit: Int = 80,
                           progress: (String) async -> Void = { _ in },
                           fetch: (BoardRequest) async throws -> Data) async -> Outcome {
        var outcome = Outcome()
        var ids = Set<String>()
        var matches: [DiscoveredJob] = []
        var checked: [String: Int] = [:]
        let boards = companies.filter { $0.enabled && $0.board != .none && !$0.boardToken.trimmed.isEmpty }
        for (n, c) in boards.enumerated() {
            await progress("Checking \(c.name) (\(n + 1) of \(boards.count))…")
            var queue = c.board.listingRequests(token: c.boardToken, terms: terms)
            guard !queue.isEmpty else {
                outcome.notes.append("\(c.name): this board link couldn't be read.")
                continue
            }
            do {
                var all: [DiscoveredJob] = []
                var i = 0
                while i < queue.count && i < 12 {
                    let data = try await fetch(queue[i])
                    outcome.requests += 1
                    all += try Boards.parse(data, kind: c.board, company: c.name, token: c.boardToken)
                    if let next = Boards.nextPage(after: data, request: queue[i], kind: c.board) { queue.append(next) }
                    i += 1
                }
                var seen = Set<String>()
                let unique = all.filter { seen.insert($0.id).inserted }
                let titled = Boards.matchingTitles(unique, terms: terms)
                checked[c.name] = unique.count
                outcome.searched.insert(c.name)
                for job in titled where ids.insert(job.id).inserted { matches.append(job) }
            } catch {
                outcome.notes.append("\(c.name): \(error.localizedDescription)")
            }
        }
        let needing = matches.indices.filter { matches[$0].descriptionHTML.trimmed.isEmpty && matches[$0].detailURL != nil }
        let reading = Array(needing.prefix(detailLimit))
        for (n, index) in reading.enumerated() {
            await progress("Reading posting \(n + 1) of \(reading.count)…")
            guard let s = matches[index].detailURL, let url = URL(string: s) else { continue }
            if let data = try? await fetch(BoardRequest(url: url)) {
                outcome.requests += 1
                try? Boards.applyDetail(data, to: &matches[index])
            }
        }
        outcome.jobs = matches.filter { locations.accepts(locationText: $0.locationForFiltering) }
        var summary: [String] = []
        for c in boards where outcome.searched.contains(c.name) {
            let kept = outcome.jobs.filter { $0.origin == c.name }.count
            let total = checked[c.name] ?? 0
            let what = c.board == .workday ? "roles its search returned" : "open roles"
            summary.append("\(c.name): \(kept) match of \(total) \(what).")
        }
        outcome.notes = summary + outcome.notes
        return outcome
    }
}

// MARK: - Listings shown in Jobs

/// A posting Job Bot found and read, waiting in Jobs › Found until it's saved or dismissed.
public struct FoundListing: Codable, Equatable, Identifiable {
    /// The board's own ID ("gh-123"), so the same posting is recognized on the next search.
    public var id: String
    public var job: Job
    /// The company in the person's list it came from.
    public var company: String
    public var firstSeen: Date
    public var lastSeen: Date
    public var viewed: Bool

    public init(id: String, job: Job, company: String, firstSeen: Date, lastSeen: Date, viewed: Bool = false) {
        self.id = id
        self.job = job
        self.company = company
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.viewed = viewed
    }
}

public struct FoundListings: Codable, Equatable {
    public var items: [FoundListing]
    /// Postings the person marked not interested (kept so they don't come back).
    public var dismissed: [String]
    public var lastSearch: Date?
    public var notes: [String]

    public init() {
        items = []
        dismissed = []
        lastSearch = nil
        notes = []
    }

    /// Adds a search's results. Listings from boards that were read but no longer show them are
    /// removed (closed, or no longer matching the search); listings from boards that couldn't be
    /// read this time are kept. Returns how many listings are new.
    @discardableResult
    public mutating func merge(_ found: [DiscoveredJob], searched: Set<String>, notes: [String] = [], now: Date = Date()) -> Int {
        let foundIDs = Set(found.map(\.id))
        let skip = Set(dismissed)
        items.removeAll { searched.contains($0.company) && !foundIDs.contains($0.id) }
        var added = 0
        for d in found where !skip.contains(d.id) {
            if let i = items.firstIndex(where: { $0.id == d.id }) {
                var job = d.toJob(now: items[i].firstSeen)
                job.id = items[i].job.id
                items[i].job = job
                items[i].lastSeen = now
            } else {
                items.append(FoundListing(id: d.id, job: d.toJob(now: now), company: d.origin, firstSeen: now, lastSeen: now))
                added += 1
            }
        }
        lastSearch = now
        self.notes = notes
        return added
    }

    public mutating func dismiss(_ id: String) {
        items.removeAll { $0.id == id }
        if !dismissed.contains(id) { dismissed.append(id) }
        if dismissed.count > 2000 { dismissed.removeFirst(dismissed.count - 2000) }
    }

    /// Takes a listing out (when it's saved to the person's jobs).
    public mutating func take(_ id: String) -> FoundListing? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    public var unviewedCount: Int { items.filter { !$0.viewed }.count }
}

// MARK: - Fit

/// How much of a posting the master resume speaks to. A reading aid for sorting, not a
/// prediction of how an application will go.
public struct Fit: Equatable {
    public enum Level: Equatable { case strong, partial, low, unknown }

    public var requiredCovered: Int
    public var requiredTotal: Int
    public var keywordsMatched: Int
    public var keywordsTotal: Int

    public var score: Double {
        let keywordShare = keywordsTotal > 0 ? Double(keywordsMatched) / Double(keywordsTotal) : nil
        if requiredTotal > 0 {
            let required = Double(requiredCovered) / Double(requiredTotal)
            return 0.75 * required + 0.25 * (keywordShare ?? required)
        }
        return keywordShare ?? 0
    }

    public var level: Level {
        if requiredTotal == 0 && keywordsTotal == 0 { return .unknown }
        if score >= 0.7 { return .strong }
        if score >= 0.4 { return .partial }
        return .low
    }

    public var summary: String {
        if requiredTotal > 0 { return "Covers \(requiredCovered) of \(requiredTotal) required" }
        if keywordsTotal > 0 { return "\(keywordsMatched) of \(keywordsTotal) keywords" }
        return "Too little detail to compare"
    }
}

extension MatchReport {
    public var fit: Fit {
        let required = requirements.filter { $0.kind == .required }
        return Fit(requiredCovered: required.filter { $0.strength != .gap }.count, requiredTotal: required.count,
                   keywordsMatched: matchedKeywords.count, keywordsTotal: matchedKeywords.count + missingKeywords.count)
    }
}
