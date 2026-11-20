import Foundation

/// Where job postings can come from, and how Job Bot is allowed to read each one.
public enum BoardKind: String, Codable, CaseIterable, Identifiable {
    /// No public job-board feed known; open the careers page in the browser instead.
    case none
    /// Greenhouse's public Job Board API (boards-api.greenhouse.io).
    case greenhouse
    /// Lever's public Postings API (api.lever.co).
    case lever
    /// Ashby's public Job Posting API (api.ashbyhq.com).
    case ashby
    /// SmartRecruiters' public Posting API (api.smartrecruiters.com).
    case smartrecruiters
    /// Workable's public job widget feed (apply.workable.com).
    case workable
    /// A Workday careers site (*.myworkdayjobs.com), read through the same public job search
    /// the site's own page uses. No sign-in.
    case workday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Careers page only"
        case .greenhouse: return "Greenhouse job board"
        case .lever: return "Lever job board"
        case .ashby: return "Ashby job board"
        case .smartrecruiters: return "SmartRecruiters job board"
        case .workable: return "Workable job board"
        case .workday: return "Workday careers site"
        }
    }

    /// Short name used in listing sources ("Greenhouse").
    public var shortName: String {
        switch self {
        case .none: return "Careers page"
        case .greenhouse: return "Greenhouse"
        case .lever: return "Lever"
        case .ashby: return "Ashby"
        case .smartrecruiters: return "SmartRecruiters"
        case .workable: return "Workable"
        case .workday: return "Workday"
        }
    }

    /// The public listing endpoint for a board (the first page, for boards with several).
    public func listingURL(token: String) -> URL? {
        let t = token.trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        switch self {
        case .none: return nil
        case .greenhouse: return URL(string: "https://boards-api.greenhouse.io/v1/boards/\(t)/jobs?content=true")
        case .lever: return URL(string: "https://api.lever.co/v0/postings/\(t)?mode=json")
        case .ashby: return URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(t)?includeCompensation=true")
        case .smartrecruiters: return URL(string: "https://api.smartrecruiters.com/v1/companies/\(t)/postings?limit=100&offset=0")
        case .workable: return URL(string: "https://apply.workable.com/api/v1/widget/accounts/\(t)?details=true")
        case .workday: return WorkdaySite(token: token)?.searchURL
        }
    }
}

public struct CompanySource: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The careers page, if the person added it.
    public var careersURL: String
    public var board: BoardKind
    public var boardToken: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, careersURL: String = "", board: BoardKind = .none, boardToken: String = "", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.careersURL = careersURL
        self.board = board
        self.boardToken = boardToken
        self.enabled = enabled
    }

    /// The board name as shown to the person (a Workday site shows its address).
    public var boardLabel: String {
        if board == .workday, let site = WorkdaySite(token: boardToken) { return site.host.components(separatedBy: ".").first ?? site.host }
        return boardToken
    }

    /// Guesses for the board name, tried in order by "Find job board" (each guess is checked
    /// against the real board before it's used).
    public var tokenGuesses: [String] {
        let base = name.components(separatedBy: CharacterSet(charactersIn: "/(")).first ?? name
        let words = base.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var out: [String] = []
        func add(_ s: String) { if !s.isEmpty && !out.contains(s) { out.append(s) } }
        add(words.joined())
        add(words.joined(separator: "-"))
        if let first = words.first { add(first) }
        let trimmed = words.filter { !["inc", "llc", "the", "company", "corporation", "education", "learning"].contains($0) }
        add(trimmed.joined())
        return out
    }
}

/// A site the person searches in their own browser (Job Bot builds the search link only).
public struct SearchSite: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// URL with {keywords} and {location} placeholders.
    public var template: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, template: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.template = template
        self.enabled = enabled
    }

    public func url(keywords: String, location: String) -> URL? {
        let k = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? keywords
        let l = location.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? location
        return URL(string: template.replacingOccurrences(of: "{keywords}", with: k).replacingOccurrences(of: "{location}", with: l))
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}

public struct DiscoverySettings: Codable, Equatable {
    public var searchTerms: [String]
    public var companies: [CompanySource]
    public var sites: [SearchSite]
    /// Which set of built-in careers links has been added (nil in libraries made before 1.0.1).
    public var careerLinksVersion: Int?
    /// Which set of job-board kinds has been connected from careers links (nil before 1.0.3).
    public var boardLinksVersion: Int?

    public static let currentCareerLinksVersion = 1
    public static let currentBoardLinksVersion = 2

    public init() {
        searchTerms = ["Assessment Specialist", "ELA Content Developer", "Item Writer"]
        companies = Self.defaultCompanies.map { Self.company(named: $0) }
        careerLinksVersion = Self.currentCareerLinksVersion
        boardLinksVersion = Self.currentBoardLinksVersion
        sites = [
            SearchSite(name: "LinkedIn", template: "https://www.linkedin.com/jobs/search/?keywords={keywords}&location={location}"),
            SearchSite(name: "Indeed", template: "https://www.indeed.com/jobs?q={keywords}&l={location}"),
            SearchSite(name: "Handshake", template: "https://app.joinhandshake.com/stu/postings?query={keywords}"),
        ]
    }

    /// A company with its built-in careers link, and its job board connected when the link
    /// points to one with a public feed.
    public static func company(named name: String) -> CompanySource {
        var c = CompanySource(name: name)
        if let link = defaultCareerLinks[name] {
            c.careersURL = link
            if let board = Boards.detect(fromURL: link) {
                c.board = board.0
                c.boardToken = board.1
            }
        }
        return c
    }

    /// Adds the built-in careers links to a library made before they existed. Only fills empty
    /// links (never replaces one the person entered), and only once. Returns how many it added.
    @discardableResult
    public mutating func addDefaultCareerLinks() -> Int {
        guard (careerLinksVersion ?? 0) < Self.currentCareerLinksVersion else { return 0 }
        var added = 0
        for i in companies.indices where companies[i].careersURL.trimmed.isEmpty {
            let name = companies[i].name.lowercased()
            guard let key = Self.defaultCareerLinks.keys.first(where: { $0.lowercased() == name }),
                  let link = Self.defaultCareerLinks[key] else { continue }
            companies[i].careersURL = link
            if companies[i].board == .none, let board = Boards.detect(fromURL: link) {
                companies[i].board = board.0
                companies[i].boardToken = board.1
            }
            added += 1
        }
        careerLinksVersion = Self.currentCareerLinksVersion
        return added
    }

    /// Connects job boards that can now be read from careers links already in the library
    /// (SmartRecruiters, Workable and Workday were added in 1.0.3). Runs once; companies that
    /// already have a board, or none detectable, are left alone. Returns how many it connected.
    @discardableResult
    public mutating func connectDetectedBoards() -> Int {
        guard (boardLinksVersion ?? 0) < Self.currentBoardLinksVersion else { return 0 }
        var connected = 0
        for i in companies.indices where companies[i].board == .none {
            guard let board = Boards.detect(fromURL: companies[i].careersURL) else { continue }
            companies[i].board = board.0
            companies[i].boardToken = board.1
            connected += 1
        }
        boardLinksVersion = Self.currentBoardLinksVersion
        return connected
    }

    /// Careers pages for the default company list (collected November 2026).
    public static let defaultCareerLinks: [String: String] = [
        "Pearson": "https://pearson.jobs/remote-jobs/new-jobs/",
        "Prodigy": "https://jobs.ashbyhq.com/prodigy-education/",
        "NWEA / Houghton Mifflin Harcourt": "https://careers.hmhco.com/search",
        "Illuminate": "https://careers.smartrecruiters.com/Renaissance",
        "DreamBox": "https://jobs.dayforcehcm.com/en-US/discoveryed/CANDIDATEPORTAL",
        "McGraw Hill": "https://careers.mheducation.com/jobs?limit=100&page=1",
        "IXL": "https://www.ixl.com/company/careers",
        "Amplify": "https://amplify.wd1.myworkdayjobs.com/Amplify_Careers",
        "ETS": "https://etscareers.pereless.com/83080/talent.cfm",
        "Renaissance": "https://careers.smartrecruiters.com/Renaissance",
        "Curriculum Associates": "https://curriculumassociates.wd5.myworkdayjobs.com/External",
        "Scholastic Education": "https://scholastic.wd5.myworkdayjobs.com/External",
        "Khan Academy": "https://www.khanacademy.org/careers#openings",
        "Kaplan": "https://ghc.wd1.myworkdayjobs.com/Kaplan_Careers",
        "Fablevision": "https://www.fablevisionstudios.com/jobs-internships",
        "Edmentum": "https://job-boards.greenhouse.io/edmentum",
        "ClassLink": "https://www.classlink.com/company/careers",
        "CommonLit": "https://jobs.lever.co/commonlit",
        "NoRedInk": "https://www.noredink.com/about/jobs/",
        "Meazure Learning": "https://workforcenow.adp.com/mascsr/default/mdf/recruitment/recruitment.html?cid=80476592-d857-4207-83c6-fe66444a7e3b&ccId=19000101_000001&lang=en_US",
        "Carnegie Learning": "https://www.paycomonline.net/v4/ats/web.php/jobs?clientkey=CDD5880F7074A7DA04A1A00A3B0CD380",
        "Duolingo": "https://careers.duolingo.com/#careers",
        "College Board": "https://collegeboard.wd1.myworkdayjobs.com/en-US/Careers",
        "Data Recognition Corporation": "https://www.datarecognitioncorp.com/career-opportunities/",
        "AIR (American Institutes for Research)": "https://www.air.org/build-career-air#grnhse_app",
        "TNTP": "https://tntp.wd5.myworkdayjobs.com/TNTP",
        "WestEd": "https://recruiting2.ultipro.com/WES1032WSTE/JobBoard/e5cebb97-720c-4bb5-8a63-deffd14ff13a?q=&o=postedDateDesc",
        "American Reading Company": "https://www.paycomonline.net/v4/ats/web.php/jobs?clientkey=E93CCC6D454104319EA9B7C781FF657C",
        "Cambium Learning / Lexia": "https://jobs.cambiumlearning.com/#/",
        "ThinkCerca": "https://thinkcerca.applytojob.com/apply",
        "PowerSchool": "https://www.powerschool.com/company/careers/#jobs-form-12",
        "Anthology": "https://careers.anthology.com/search/jobs",
        "Pear Assessment": "https://www.peardeck.com/products/pear-assessment",
        "Discovery Education": "https://jobs.dayforcehcm.com/en-US/discoveryed/CANDIDATEPORTAL",
        "Savvas": "https://jobs.dayforcehcm.com/en-US/k12l/CANDIDATEPORTAL",
        "Cognia": "https://workforcenow.adp.com/mascsr/default/mdf/recruitment/recruitment.html?cid=ebbb9e9f-4b7c-4d22-9984-b930aaf04fa6&ccId=19000101_000001&type=MP&lang=en_US&selectedMenuKey=CareerCenter",
        "Riverside Insights": "https://apply.workable.com/riverside-insights/",
        "PSI Services": "https://psionline.rec.pro.ukg.net/PSI1500PSIL/JobBoard/287b933d-50bd-4acb-b709-75def54bf55f",
        "Instructure": "https://www.instructure.com/about/careers#comparably",
        "Assessment Systems Corporation": "https://assess.applytojob.com/",
        "Scantron": "https://www.linkedin.com/jobs/scantron-jobs-worldwide?f_C=79728%2C14550&trk=top-card_top-card-primary-button-top-card-primary-cta&position=1&pageNum=0",
        "Seesaw": "https://boards.greenhouse.io/seesaw",
    ]

    public static let defaultCompanies = [
        "Pearson", "Prodigy", "NWEA / Houghton Mifflin Harcourt", "Illuminate", "DreamBox", "McGraw Hill", "IXL", "Amplify",
        "ETS", "Renaissance", "Curriculum Associates", "Scholastic Education", "Khan Academy", "Kaplan", "Fablevision",
        "Edmentum", "ClassLink", "CommonLit", "NoRedInk", "Meazure Learning", "Carnegie Learning", "Duolingo",
        "College Board", "Data Recognition Corporation", "AIR (American Institutes for Research)", "TNTP", "WestEd",
        "American Reading Company", "Cambium Learning / Lexia", "ThinkCerca", "PowerSchool", "Anthology", "Pear Assessment",
        "Discovery Education", "Savvas", "Cognia", "Riverside Insights", "PSI Services", "Instructure",
        "Assessment Systems Corporation", "Scantron", "Seesaw",
    ]
}

/// A posting found through a public job-board feed, before it's saved.
public struct DiscoveredJob: Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var employer: String
    public var location: String
    public var url: String
    public var source: String
    public var posted: Date?
    public var descriptionHTML: String
    public var salary: SalaryInfo?
    public var remote: Bool
    /// Where the full posting is read from, for boards whose list leaves out the description.
    public var detailURL: String?
    /// The company in the person's list this came from (the employer can differ, for example
    /// when two companies share one board).
    public var origin: String
    public var board: BoardKind

    public init(id: String, title: String, employer: String, location: String, url: String, source: String, posted: Date?,
                descriptionHTML: String, salary: SalaryInfo? = nil, remote: Bool = false, detailURL: String? = nil,
                origin: String? = nil, board: BoardKind = .none) {
        self.id = id
        self.title = title
        self.employer = employer
        self.location = location
        self.url = url
        self.source = source
        self.posted = posted
        self.descriptionHTML = descriptionHTML
        self.salary = salary
        self.remote = remote
        self.detailURL = detailURL
        self.origin = origin ?? employer
        self.board = board
    }

    public func toJob(now: Date = Date()) -> Job {
        let text = HTMLText.text(fromHTML: HTMLText.decodeEntities(descriptionHTML))
        var job = Job(title: title, employer: employer, location: location, source: source, url: url, postedDate: posted,
                      dateFound: now, descriptionText: text)
        job.parsed = JobParser.parse(text, source: source, date: now)
        if remote { job.parsed.remote = true }
        if let s = salary { job.parsed.salary = s }
        if job.location.isEmpty, let l = job.parsed.location { job.location = l }
        return job
    }

    public var locationForFiltering: String { remote ? location + " Remote" : location }
}

public enum Boards {
    /// Recognizes board links: boards.greenhouse.io/acme, jobs.lever.co/acme, jobs.ashbyhq.com/acme.
    public static func detect(fromURL s: String) -> (BoardKind, String)? {
        guard let url = URL(string: s.trimmed), let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if host.hasSuffix("greenhouse.io"), let first = parts.first {
            if first == "embed", let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "for" })?.value {
                return (.greenhouse, token)
            }
            if first != "v1" { return (.greenhouse, first) }
            if parts.count >= 3, parts[1] == "boards" { return (.greenhouse, parts[2]) }
        }
        if host == "jobs.lever.co", let first = parts.first { return (.lever, first) }
        if host == "jobs.ashbyhq.com", let first = parts.first { return (.ashby, first) }
        if host == "careers.smartrecruiters.com" || host == "jobs.smartrecruiters.com", let first = parts.first {
            return (.smartrecruiters, first)
        }
        if host == "apply.workable.com", let first = parts.first, first != "j", first != "api" { return (.workable, first) }
        if host.hasSuffix(".myworkdayjobs.com") {
            // Skip a locale segment ("en-US") and anything after the site name ("/job/...").
            let site = parts.first(where: { p in
                !(p.count == 5 && p.dropFirst(2).first == "-" && p.prefix(2).allSatisfy(\.isLowercase))
            })
            if let site, site != "wday" { return (.workday, "\(host)/\(site)") }
        }
        return nil
    }

    public static func parse(_ data: Data, kind: BoardKind, company: String, token: String = "", now: Date = Date()) throws -> [DiscoveredJob] {
        let obj = try JSONSerialization.jsonObject(with: data)
        let jobs = try parseObject(obj, kind: kind, company: company, token: token, now: now)
        return jobs.map { j in
            var j = j
            j.board = kind
            j.origin = company
            return j
        }
    }

    static func parseObject(_ obj: Any, kind: BoardKind, company: String, token: String, now: Date) throws -> [DiscoveredJob] {
        switch kind {
        case .none:
            return []
        case .smartrecruiters, .workable, .workday:
            return ListingFeeds.parse(obj, kind: kind, company: company, token: token, now: now)
        case .greenhouse:
            guard let dict = obj as? [String: Any], let jobs = dict["jobs"] as? [[String: Any]] else { return [] }
            return jobs.map { j in
                let loc = ((j["location"] as? [String: Any])?["name"] as? String) ?? ""
                return DiscoveredJob(id: "gh-\(j["id"] ?? "")", title: (j["title"] as? String) ?? "", employer: company,
                                     location: loc, url: (j["absolute_url"] as? String) ?? "", source: "Greenhouse (\(company))",
                                     posted: HTMLText.parseDate(j["updated_at"] as? String),
                                     descriptionHTML: (j["content"] as? String) ?? "",
                                     remote: loc.lowercased().contains("remote"))
            }
        case .lever:
            guard let jobs = obj as? [[String: Any]] else { return [] }
            return jobs.map { j in
                let cats = j["categories"] as? [String: Any] ?? [:]
                let loc = (cats["location"] as? String) ?? ((cats["allLocations"] as? [String])?.joined(separator: "; ") ?? "")
                var html = (j["description"] as? String) ?? ""
                for list in (j["lists"] as? [[String: Any]]) ?? [] {
                    html += "<h3>\((list["text"] as? String) ?? "")</h3><ul>\((list["content"] as? String) ?? "")</ul>"
                }
                html += (j["additional"] as? String) ?? ""
                let created = (j["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                let workplace = (j["workplaceType"] as? String) ?? ""
                var salary: SalaryInfo?
                if let range = j["salaryRange"] as? [String: Any] {
                    let lo = HTMLText.number(range["min"]), hi = HTMLText.number(range["max"])
                    let interval = ((range["interval"] as? String) ?? "").lowercased()
                    let period: PayPeriod = interval.contains("hour") ? .hour : interval.contains("month") ? .month : .year
                    if lo != nil || hi != nil {
                        var s = SalaryInfo(minimum: lo, maximum: hi, currency: (range["currency"] as? String) ?? "USD", period: period,
                                           text: "", source: "Lever (\(company))", date: now)
                        s.text = s.display
                        salary = s
                    }
                }
                return DiscoveredJob(id: "lv-\((j["id"] as? String) ?? UUID().uuidString)", title: (j["text"] as? String) ?? "",
                                     employer: company, location: loc, url: (j["hostedUrl"] as? String) ?? "",
                                     source: "Lever (\(company))", posted: created, descriptionHTML: html, salary: salary,
                                     remote: workplace.lowercased() == "remote" || loc.lowercased().contains("remote"))
            }
        case .ashby:
            guard let dict = obj as? [String: Any], let jobs = dict["jobs"] as? [[String: Any]] else { return [] }
            return jobs.compactMap { j in
                if let listed = j["isListed"] as? Bool, !listed { return nil }
                let loc = (j["location"] as? String) ?? ""
                return DiscoveredJob(id: "ab-\((j["id"] as? String) ?? UUID().uuidString)", title: (j["title"] as? String) ?? "",
                                     employer: company, location: loc, url: (j["jobUrl"] as? String) ?? "",
                                     source: "Ashby (\(company))", posted: HTMLText.parseDate(j["publishedAt"] as? String),
                                     descriptionHTML: (j["descriptionHtml"] as? String) ?? "",
                                     remote: (j["isRemote"] as? Bool) ?? loc.lowercased().contains("remote"))
            }
        }
    }

    /// Keeps postings in the chosen locations whose title matches a search term.
    public static func filter(_ jobs: [DiscoveredJob], terms: [String], locations: LocationFilter) -> [DiscoveredJob] {
        matchingTitles(jobs, terms: terms).filter { locations.accepts(locationText: $0.locationForFiltering) }
    }

    /// Keeps postings whose title matches a search term: all of its words, or two-thirds of
    /// them ("Assessment Content Specialist" matches "Assessment Specialist").
    public static func matchingTitles(_ jobs: [DiscoveredJob], terms: [String]) -> [DiscoveredJob] {
        let termWords = terms.map { TextTools.terms($0) }.filter { !$0.isEmpty }
        guard !termWords.isEmpty else { return jobs }
        return jobs.filter { j in
            let titleTerms = TextTools.terms(j.title)
            if termWords.contains(where: { $0.isSubset(of: titleTerms) }) { return true }
            return termWords.contains { t in Double(t.intersection(titleTerms).count) / Double(t.count) >= 0.66 }
        }
    }
}

/// Spots postings saved twice.
public enum Duplicates {
    public static func canonicalURL(_ s: String) -> String {
        guard var c = URLComponents(string: s.trimmed) else { return s.trimmed.lowercased() }
        c.fragment = nil
        c.queryItems = c.queryItems?.filter { item in
            let n = item.name.lowercased()
            return !(n.hasPrefix("utm_") || ["ref", "source", "src", "trk", "gh_src", "lever-source", "refid"].contains(n))
        }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var out = (c.string ?? s).lowercased()
        if out.hasSuffix("/") { out.removeLast() }
        return out.replacingOccurrences(of: "://www.", with: "://")
    }

    /// The saved job this one duplicates, if any.
    public static func match(for job: Job, in jobs: [Job]) -> Job? {
        let url = job.url.isEmpty ? "" : canonicalURL(job.url)
        let key = TextTools.key(job.title) + "|" + TextTools.key(job.employer)
        return jobs.first { other in
            guard other.id != job.id else { return false }
            if !url.isEmpty && !other.url.isEmpty && canonicalURL(other.url) == url { return true }
            let otherKey = TextTools.key(other.title) + "|" + TextTools.key(other.employer)
            return !job.title.isEmpty && !job.employer.isEmpty && otherKey == key
                && (job.location.isEmpty || other.location.isEmpty || TextTools.key(job.location) == TextTools.key(other.location))
        }
    }
}

/// Sites whose terms don't allow automated access: Job Bot never downloads their pages and asks
/// for the text instead.
public enum FetchPolicy {
    public static let noFetchHosts = ["linkedin.com", "indeed.com", "joinhandshake.com", "glassdoor.com", "ziprecruiter.com",
                                      "monster.com", "simplyhired.com", "dice.com", "wellfound.com", "angel.co"]

    public static func blockedReason(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return "That doesn't look like a web address." }
        if let site = noFetchHosts.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return "\(site) doesn't allow automated access, so Job Bot won't download the page. Open it in your browser, copy the job description, and paste it here."
        }
        guard url.scheme == "https" || url.scheme == "http" else { return "Only web addresses (https://…) can be read." }
        return nil
    }
}
