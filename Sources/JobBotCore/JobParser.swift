import Foundation

/// Reads a job description into responsibilities, required and preferred qualifications,
/// keywords, location and pay.
public enum JobParser {
    enum Bucket { case responsibilities, required, preferred, overview, other }

    static let headerPhrases: [(Bucket, [String])] = [
        (.preferred, ["preferred qualifications", "preferred skills", "preferred experience", "preferred", "nice to have",
                      "nice-to-have", "nice to haves", "bonus points", "bonus", "desired qualifications", "desired skills",
                      "desired experience", "additional qualifications", "pluses", "it's a plus if", "extra credit",
                      "ideally you have", "ideally, you have", "even better if", "preferred requirements"]),
        (.required, ["requirements", "qualifications", "required qualifications", "minimum qualifications", "basic qualifications",
                     "what you bring", "what you'll bring", "what you will bring", "must have", "must-haves", "must haves",
                     "who you are", "required skills", "you have", "about you", "what we're looking for",
                     "what we are looking for", "skills and experience", "education and experience", "required experience",
                     "experience and skills", "job requirements", "knowledge, skills, and abilities", "knowledge, skills and abilities",
                     "skills, knowledge and abilities", "ksas", "you might be a fit if", "you'll thrive if", "your background",
                     "experience", "education", "skills", "minimum requirements", "position requirements", "the ideal candidate",
                     "required education and experience", "what you need", "you should have", "competencies"]),
        (.responsibilities, ["responsibilities", "key responsibilities", "what you'll do", "what you will do", "duties",
                             "essential duties", "essential functions", "essential duties and responsibilities", "job duties",
                             "your impact", "in this role", "day to day", "day-to-day", "you will", "job responsibilities",
                             "primary responsibilities", "what you'll be doing", "what you will be doing",
                             "how you'll contribute", "overview of responsibilities", "what you'll work on",
                             "major responsibilities", "scope of work"]),
        (.overview, ["the role", "about the role", "role overview", "the opportunity", "position summary", "job summary",
                     "your role", "job description", "overview", "about the position", "about this role", "about the job",
                     "position overview", "job overview"]),
        (.other, ["benefits", "compensation", "salary", "pay", "perks", "what we offer", "why join us", "pay range",
                  "compensation and benefits", "total rewards", "about us", "about the company", "who we are", "our mission",
                  "equal opportunity", "equal opportunity employer", "eeo statement", "our values", "why you'll love working here",
                  "location", "work environment", "physical requirements", "travel", "how to apply", "application process",
                  "our commitment", "diversity, equity, and inclusion", "accommodations", "salary range", "pay transparency"]),
    ]

    static func bucket(forHeader line: String) -> Bucket? {
        // A bullet is never a heading ("• Classroom teaching experience").
        if TextTools.bulletText(line) != nil { return nil }
        var key = line.trimmed.lowercased()
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—*#•"))
        key = key.replacingOccurrences(of: "’", with: "'").squashed
        guard !key.isEmpty, key.split(separator: " ").count <= 9 else { return nil }
        let endsAsHeader = line.trimmed.hasSuffix(":") || TextTools.looksLikeHeading(line) || key.split(separator: " ").count <= 6
        guard endsAsHeader, !line.trimmed.hasSuffix(".") else { return nil }
        for (bucket, phrases) in headerPhrases {
            if phrases.contains(key) { return bucket }
        }
        for (bucket, phrases) in headerPhrases {
            // Only multi-word phrases match partially ("preferred qualifications include").
            for p in phrases where p.contains(" ") && (key.hasPrefix(p + " ") || key.hasPrefix(p + ":") || key.hasSuffix(" " + p)) {
                return bucket
            }
        }
        if key.hasPrefix("about ") && key.split(separator: " ").count <= 5 { return .other }
        return nil
    }

    public static func parse(_ text: String, source: String = "Job posting", date: Date = Date()) -> ParsedJob {
        let lines = ResumeParser.cleanLines(text, joinWrappedBullets: false)
        var parsed = ParsedJob()
        var current: Bucket? = nil
        var sawHeader = false
        var buckets: [Bucket: [String]] = [:]

        for line in lines {
            if let b = bucket(forHeader: line) {
                current = b
                sawHeader = true
                continue
            }
            // "Qualifications: 3+ years..." on one line.
            if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) < 40 {
                let head = String(line[..<colon])
                let rest = String(line[line.index(after: colon)...]).trimmed
                if let b = bucket(forHeader: head + ":"), !rest.isEmpty, !head.lowercased().contains("location") {
                    current = b
                    sawHeader = true
                    buckets[b, default: []].append(contentsOf: items(from: rest))
                    continue
                }
            }
            let target = current ?? .other
            buckets[target, default: []].append(contentsOf: items(from: line))
        }

        if !sawHeader || (buckets[.responsibilities, default: []].isEmpty && buckets[.required, default: []].isEmpty) {
            // No usable headings: sort sentence by sentence.
            var re: [Bucket: [String]] = [:]
            var all: [String] = []
            for b in [Bucket.other, .overview, .responsibilities, .required, .preferred] {
                all.append(contentsOf: buckets[b] ?? [])
            }
            for item in all {
                re[classify(item), default: []].append(item)
            }
            buckets = re
        }

        // Overview paragraphs: keep only sentences that read like duties or requirements.
        for item in buckets[.overview] ?? [] {
            buckets[classify(item), default: []].append(item)
        }
        buckets[.overview] = nil

        // Inside requirements, items that say "preferred" or "a plus" are preferred.
        var required: [String] = []
        var preferred = buckets[.preferred] ?? []
        for item in buckets[.required] ?? [] {
            if isPreferredCue(item) { preferred.append(item) } else { required.append(item) }
        }
        parsed.responsibilities = dedupe(buckets[.responsibilities] ?? [])
        parsed.requiredQualifications = dedupe(required)
        parsed.preferredQualifications = dedupe(preferred)
        parsed.other = dedupe(buckets[.other] ?? [])
        parsed.keywords = keywords(responsibilities: parsed.responsibilities, required: parsed.requiredQualifications,
                                   preferred: parsed.preferredQualifications, fallback: text)
        parsed.salary = salary(in: text, source: source, date: date)
        let loc = location(in: lines)
        parsed.location = loc.text
        parsed.remote = loc.remote
        parsed.employmentType = employmentType(in: text)
        return parsed
    }

    /// Bullet items stay whole; paragraphs are split into sentences.
    static func items(from line: String) -> [String] {
        if let b = TextTools.bulletText(line) { return [WritingRules.cleanSpacing(b)] }
        let sentences = TextTools.sentences(line)
        if sentences.count <= 1 { return [line.trimmed] }
        return sentences
    }

    static func isPreferredCue(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("preferred") || l.contains("a plus") || l.contains("nice to have") || l.contains("is a bonus")
            || l.contains("desirable") || l.contains("ideally") || l.contains("bonus if") || l.hasSuffix(" a plus.")
    }

    static let qualificationCues = ["experience", "degree", "years", "proficien", "knowledge of", "familiar", "ability to",
                                    "skills in", "skilled in", "certification", "certified", "bachelor", "master's",
                                    "understanding of", "background in", "expertise", "fluency", "fluent", "must have",
                                    "required", "demonstrated", "track record", "comfortable with", "strong ", "excellent "]

    static func classify(_ item: String) -> Bucket {
        let l = item.lowercased()
        if isPreferredCue(item) { return .preferred }
        let first = TextTools.words(item).first ?? ""
        if Lexicon.responsibilityVerbs.contains(first) || l.hasPrefix("you will") || l.hasPrefix("you'll") { return .responsibilities }
        if qualificationCues.contains(where: { l.contains($0) }) { return .required }
        if l.contains("will be responsible") || l.contains("responsible for") { return .responsibilities }
        return .other
    }

    static func dedupe(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for i in items {
            let t = i.trimmed
            guard t.count > 2 else { continue }
            let k = TextTools.key(t)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(t)
        }
        return out
    }

    // MARK: Keywords

    /// The terms a reviewer or an applicant tracking system is likely to look for, most
    /// important first. Required qualifications count most.
    public static func keywords(responsibilities: [String], required: [String], preferred: [String], fallback: String) -> [String] {
        var scores: [String: Double] = [:]
        var display: [String: String] = [:]
        func add(_ text: String, weight: Double) {
            for s in Lexicon.skills(in: text) {
                scores[s, default: 0] += weight
                if display[s] == nil { display[s] = displayForm(of: s, in: text) }
            }
            for p in TextTools.phrases(in: text) where p.contains(" ") || p.count >= 3 {
                let k = TextTools.words(p).joined(separator: " ")
                scores[k, default: 0] += weight * 0.8
                if display[k] == nil { display[k] = displayForm(of: k, in: text) }
            }
            for name in properTerms(in: text) {
                let k = name.lowercased()
                scores[k, default: 0] += weight * 0.7
                if display[k] == nil { display[k] = name }
            }
        }
        let anyStructured = !(responsibilities.isEmpty && required.isEmpty && preferred.isEmpty)
        if anyStructured {
            required.forEach { add($0, weight: 3) }
            preferred.forEach { add($0, weight: 1.5) }
            responsibilities.forEach { add($0, weight: 2) }
        } else {
            add(fallback, weight: 1)
        }
        // Remove generic single words that slip through.
        let generic: Set<String> = ["assessment", "writing", "reading", "editing", "research", "training", "teaching",
                                    "communication", "collaboration", "review", "alignment", "scoring", "leadership"]
        let ranked = scores.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
        var out: [String] = []
        for (k, v) in ranked {
            if generic.contains(k) && v < 4 { continue }
            // Skip a term already covered by a longer chosen one.
            if out.contains(where: { $0.lowercased().contains(k) && $0.lowercased() != k }) { continue }
            out.append(display[k] ?? k)
            if out.count >= 30 { break }
        }
        return out
    }

    /// The phrase as the posting wrote it ("Item Writing", "QTI", "Bachelor's degree").
    static func displayForm(of phrase: String, in text: String) -> String {
        // A canonical phrase may appear in the posting as one of its equivalents.
        let canon = TextTools.canonical[phrase] ?? phrase
        if let group = TextTools.synonymGroups.first(where: { $0.first == canon }) {
            for variant in group.sorted(by: { $0.count > $1.count }) where variant.count >= 3 {
                if let r = Tailor.wordRange(of: variant, in: text) {
                    let found = String(text[r])
                    return found == found.uppercased() || found.first?.isLowercase == true ? found : (found.split(separator: " ").count > 1 ? found : found.lowercased())
                }
            }
        }
        if let r = text.range(of: phrase, options: .caseInsensitive) {
            let found = String(text[r])
            // Keep acronyms upper case; otherwise use the posting's casing unless it's a sentence start.
            if found == found.uppercased() { return found }
            return found.first?.isUppercase == true && phrase.split(separator: " ").count == 1 ? found.lowercased() : found
        }
        return phrase
    }

    /// Acronyms and product names: "QTI", "Smartsheet", "Articulate Storyline".
    static func properTerms(in text: String) -> [String] {
        var out: [String] = []
        let skip: Set<String> = ["we", "our", "you", "the", "this", "a", "an", "in", "and", "or", "of", "for", "to", "with",
                                 "as", "at", "by", "on", "is", "are", "be", "will", "must", "may", "if", "eeo", "usd",
                                 "us", "u.s", "ii", "iii", "job", "role", "team", "about", "experience", "bachelor's",
                                 "master's", "remote", "hybrid", "full-time", "part-time", "inc", "llc", "ela", "k-12"]
        for sentence in TextTools.sentences(text) {
            let tokens = sentence.split(separator: " ").map { String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "+#"))) }
            for (i, t) in tokens.enumerated() where i > 0 && t.count >= 2 {
                let lower = t.lowercased()
                if skip.contains(lower) || TextTools.stopwords.contains(lower) { continue }
                let isAcronym = t.count <= 6 && t.allSatisfy { $0.isUppercase || $0.isNumber } && t.contains(where: { $0.isLetter })
                let isCamel = t.dropFirst().contains(where: { $0.isUppercase }) && t.contains(where: { $0.isLowercase })
                if isAcronym || isCamel { out.append(t) }
            }
        }
        return out
    }

    // MARK: Pay, location, type

    static let amount = "(\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?|\\d+(?:\\.\\d+)?)\\s?([kK])?"
    static let periodWords = "(?:\\s*(?:/|per|an|a)\\s*(hour|hr|year|yr|annum|annually|month|mo|week|wk|day))?"
    static let rangePattern = Rx("(?:\\$|usd\\s?)\\s?\(amount)\\s*(?:-|–|—|to)\\s*(?:\\$|usd\\s?)?\\s?\(amount)\(periodWords)")
    static let singlePattern = Rx("(?:\\$|usd\\s?)\\s?\(amount)\\s*(?:/|per|an|a)\\s*(hour|hr|year|yr|annum|month|mo|week|wk|day)")

    public static func salary(in text: String, source: String = "Job posting", date: Date = Date()) -> SalaryInfo? {
        func value(_ n: String, _ k: String) -> Double? {
            guard var v = Double(n.replacingOccurrences(of: ",", with: "")) else { return nil }
            if !k.isEmpty { v *= 1000 }
            return v
        }
        func period(_ word: String, lo: Double) -> PayPeriod {
            switch word.lowercased() {
            case "hour", "hr": return .hour
            case "month", "mo": return .month
            case "week", "wk": return .week
            case "day": return .day
            case "year", "yr", "annum", "annually": return .year
            default: return lo < 300 ? .hour : .year
            }
        }
        if let m = rangePattern.firstMatch(text), let lo = value(m[1], m[2]), let hi = value(m[3], m[4]) {
            let loAdj = (m[2].isEmpty && !m[4].isEmpty && lo < 1000) ? lo * 1000 : lo
            guard hi >= 7 else { return nil }
            return SalaryInfo(minimum: loAdj, maximum: hi, period: period(m[5], lo: loAdj), text: m[0].trimmed, source: source, date: date)
        }
        if let m = singlePattern.firstMatch(text), let v = value(m[1], m[2]) {
            return SalaryInfo(minimum: v, maximum: v, period: period(m[3], lo: v), text: m[0].trimmed, source: source, date: date)
        }
        return nil
    }

    public static func location(in lines: [String]) -> (text: String?, remote: Bool) {
        var text: String?
        var remote = false
        for line in lines.prefix(400) {
            let l = line.lowercased()
            if l.hasPrefix("location") || l.hasPrefix("job location") || l.hasPrefix("work location") {
                if let colon = line.firstIndex(of: ":") {
                    let v = String(line[line.index(after: colon)...]).trimmed
                    if !v.isEmpty && text == nil { text = v }
                }
            }
            let remoteCues = ["fully remote", "100% remote", "remote position", "remote role", "this is a remote",
                              "work from home", "remote (", "remote -", "remote, ", "remote–", "remote in the us",
                              "remote within", "remote opportunity", "remote-first", "location: remote", "telecommute"]
            if remoteCues.contains(where: { l.contains($0) }) || l == "remote" { remote = true }
        }
        if text == nil {
            for line in lines.prefix(60) {
                if let m = Patterns.cityState.firstMatch(line) {
                    text = m[0]
                    break
                }
            }
        }
        if let t = text, t.lowercased().contains("remote") { remote = true }
        return (text, remote)
    }

    static func employmentType(in text: String) -> String? {
        let l = text.lowercased()
        for (cue, label) in [("full-time", "Full time"), ("full time", "Full time"), ("part-time", "Part time"),
                             ("part time", "Part time"), ("contract", "Contract"), ("freelance", "Freelance"),
                             ("temporary", "Temporary"), ("internship", "Internship")] where l.contains(cue) {
            return label
        }
        return nil
    }

    // MARK: Whole postings

    /// Builds a job from pasted text: the first short line is often the title.
    public static func job(fromText text: String, url: String = "", source: String = "Pasted description", date: Date = Date()) -> Job {
        let lines = ResumeParser.cleanLines(text, joinWrappedBullets: false)
        var job = Job(source: source, url: url, dateFound: date, descriptionText: text.trimmed)
        job.parsed = parse(text, source: source, date: date)
        if let first = lines.first, first.split(separator: " ").count <= 10, !first.hasSuffix("."), bucket(forHeader: first) == nil {
            job.title = first
            if lines.count > 1 {
                let second = lines[1]
                if second.split(separator: " ").count <= 6, !second.hasSuffix("."), bucket(forHeader: second) == nil,
                   !Patterns.cityState.matches(second), !second.lowercased().contains("remote") {
                    job.employer = second
                }
            }
        }
        if let l = job.parsed.location { job.location = l } else if job.parsed.remote { job.location = "Remote" }
        if let cue = HTMLText.closedCue(in: text) {
            job.expired = true
            job.expiredReason = "The posting says “\(cue)”."
        }
        return job
    }

    /// Builds a job from a downloaded page, preferring the page's structured posting data.
    public static func job(fromHTML html: String, url: String, date: Date = Date()) -> Job {
        let host = URL(string: url)?.host ?? "the web"
        let source = "Job page (\(host))"
        let postings = HTMLText.jobPostings(fromHTML: html)
        if let p = postings.first, let descHTML = p.descriptionHTML, !descHTML.trimmed.isEmpty {
            let descText = HTMLText.text(fromHTML: HTMLText.decodeEntities(descHTML))
            var job = Job(title: p.title ?? "", employer: p.employer ?? "", location: p.location ?? "", source: source, url: url,
                          postedDate: p.datePosted, dateFound: date, validThrough: p.validThrough, descriptionText: descText)
            job.parsed = parse(descText, source: source, date: date)
            if p.remote { job.parsed.remote = true }
            if let s = p.salary {
                var s2 = s
                s2.source = "Job page (\(host))"
                s2.date = date
                job.parsed.salary = s2
            }
            if let t = p.employmentType { job.parsed.employmentType = t }
            if job.location.isEmpty, let l = job.parsed.location { job.location = l }
            if let v = p.validThrough, v < date {
                job.expired = true
                job.expiredReason = "The page says applications closed on \(DateFormatter.localizedString(from: v, dateStyle: .medium, timeStyle: .none))."
            }
            return job
        }
        let text = HTMLText.text(fromHTML: html)
        var job = Self.job(fromText: text, url: url, source: source, date: date)
        if let t = HTMLText.title(fromHTML: html) {
            let parts = t.components(separatedBy: CharacterSet(charactersIn: "|–—-")).map { $0.trimmed }.filter { !$0.isEmpty }
            if let first = parts.first { job.title = first }
            if parts.count > 1, job.employer.isEmpty { job.employer = parts[1] }
        }
        if job.employer.isEmpty, let site = HTMLText.siteName(fromHTML: html) { job.employer = site }
        return job
    }
}

extension WritingRules {
    /// Collapses whitespace without touching punctuation.
    public static func cleanSpacing(_ s: String) -> String { s.squashed }
}
