import Foundation

public struct Evidence: Codable, Equatable, Hashable {
    public var unit: ProfileUnit
    /// The terms the requirement and this profile detail share.
    public var sharedTerms: [String]
    public var score: Double
}

public enum MatchStrength: String, Codable, Comparable {
    case gap, partial, strong

    public static func < (a: MatchStrength, b: MatchStrength) -> Bool {
        let order: [MatchStrength] = [.gap, .partial, .strong]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }

    public var title: String {
        switch self {
        case .strong: return "Supported"
        case .partial: return "Partly supported"
        case .gap: return "No evidence found"
        }
    }
}

public enum RequirementKind: String, Codable {
    case required, preferred, responsibility

    public var title: String {
        switch self {
        case .required: return "Required"
        case .preferred: return "Preferred"
        case .responsibility: return "Responsibility"
        }
    }
}

public struct RequirementMatch: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var kind: RequirementKind
    public var strength: MatchStrength
    public var evidence: [Evidence]
    /// Plain-language notes, e.g. "Your listed roles add up to about 9 years".
    public var notes: [String]
    /// Terms in the requirement that nothing in the profile mentions.
    public var missingTerms: [String]
}

public struct FollowUpQuestion: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var question: String
    /// The requirement that prompted it.
    public var requirement: String
}

public struct MatchReport: Codable, Equatable {
    public var requirements: [RequirementMatch]
    public var matchedKeywords: [String]
    public var missingKeywords: [String]
    public var followUps: [FollowUpQuestion]
    /// Years of experience computed from the dates in the profile (nil when there are no dates).
    public var profileYears: Double?

    /// Share of required qualifications with at least partial support (0...1). Not a prediction
    /// of anything: just how much of the list the profile speaks to.
    public var requiredCoverage: Double {
        let req = requirements.filter { $0.kind == .required }
        guard !req.isEmpty else { return 0 }
        let supported = req.filter { $0.strength != .gap }.count
        return Double(supported) / Double(req.count)
    }

    public var gaps: [RequirementMatch] { requirements.filter { $0.strength == .gap && $0.kind != .responsibility } }
}

public enum Matcher {
    public static func compare(profile: Profile, job: Job, now: Date = Date()) -> MatchReport {
        let units = profile.units(includeHidden: false)
        let unitTerms = units.map { TextTools.terms($0.text) }
        let years = experienceYears(profile, now: now)

        var requirements: [RequirementMatch] = []
        func add(_ items: [String], kind: RequirementKind) {
            for (i, text) in items.enumerated() {
                let rm = match(requirement: text, kind: kind, index: i, units: units, unitTerms: unitTerms, profile: profile, years: years)
                requirements.append(rm)
            }
        }
        add(job.parsed.requiredQualifications, kind: .required)
        add(job.parsed.preferredQualifications, kind: .preferred)
        add(job.parsed.responsibilities, kind: .responsibility)

        // Keywords
        let corpus = profile.corpus
        let corpusTerms = TextTools.terms(corpus)
        let corpusWords = " " + TextTools.words(corpus).joined(separator: " ") + " "
        var matched: [String] = []
        var missing: [String] = []
        for k in job.parsed.keywords {
            if keywordPresent(k, corpusTerms: corpusTerms, corpusWords: corpusWords) { matched.append(k) } else { missing.append(k) }
        }

        // Follow-up questions for unsupported required and preferred items.
        var followUps: [FollowUpQuestion] = []
        for r in requirements where r.strength == .gap && r.kind != .responsibility {
            followUps.append(FollowUpQuestion(id: r.id, question: question(for: r), requirement: r.text))
        }
        for r in requirements where r.strength == .partial && r.kind == .required && !r.missingTerms.isEmpty {
            let terms = r.missingTerms.prefix(3).joined(separator: ", ")
            followUps.append(FollowUpQuestion(id: r.id + "-detail",
                                              question: "Your profile partly covers “\(r.text)”. Do you have experience with \(terms) you could add? If so, where and what did you do?",
                                              requirement: r.text))
        }
        return MatchReport(requirements: requirements, matchedKeywords: matched, missingKeywords: missing,
                           followUps: followUps, profileYears: years)
    }

    static func keywordPresent(_ keyword: String, corpusTerms: Set<String>, corpusWords: String) -> Bool {
        let k = TextTools.words(keyword).joined(separator: " ")
        if corpusWords.contains(" " + k + " ") { return true }
        if let canon = TextTools.canonical[k], corpusTerms.contains(canon) { return true }
        let kTerms = TextTools.terms(keyword)
        guard !kTerms.isEmpty else { return false }
        return kTerms.isSubset(of: corpusTerms)
    }

    static func match(requirement text: String, kind: RequirementKind, index: Int, units: [ProfileUnit], unitTerms: [Set<String>],
                      profile: Profile, years: Double?) -> RequirementMatch {
        let reqTerms = TextTools.terms(text)
        let id = "\(kind.rawValue)-\(index)-\(TextTools.key(text).prefix(24))"
        var evidence: [Evidence] = []
        for (i, unit) in units.enumerated() {
            let shared = reqTerms.intersection(unitTerms[i])
            guard !shared.isEmpty else { continue }
            // Phrases (with spaces) count double: they carry more meaning than single words.
            let weight = shared.reduce(0.0) { $0 + ($1.contains(" ") ? 2.0 : 1.0) }
            let denom = reqTerms.reduce(0.0) { $0 + ($1.contains(" ") ? 2.0 : 1.0) }
            let score = denom > 0 ? weight / denom : 0
            evidence.append(Evidence(unit: unit, sharedTerms: shared.sorted(), score: score))
        }
        evidence.sort { $0.score > $1.score }
        evidence = Array(evidence.prefix(4))

        var notes: [String] = []
        var strength: MatchStrength
        let best = evidence.first?.score ?? 0
        let combined = Set(evidence.flatMap { $0.sharedTerms })
        let combinedWeight = combined.reduce(0.0) { $0 + ($1.contains(" ") ? 2.0 : 1.0) }
        let denom = max(1.0, reqTerms.reduce(0.0) { $0 + ($1.contains(" ") ? 2.0 : 1.0) })
        let coverage = combinedWeight / denom
        if best >= 0.5 || coverage >= 0.6 || evidence.contains(where: { $0.sharedTerms.contains { $0.contains(" ") } && $0.score >= 0.34 }) {
            strength = .strong
        } else if best >= 0.2 || coverage >= 0.3 {
            strength = .partial
        } else {
            strength = .gap
        }
        // Weak single-word overlaps aren't evidence.
        if strength == .gap { evidence = [] }

        // Years of experience ("3+ years of experience").
        if let needed = requiredYears(in: text) {
            if let y = years {
                let rounded = (y * 10).rounded() / 10
                if y + 0.01 >= needed {
                    notes.append("The dates in your experience section add up to about \(format(rounded)) years. The posting asks for \(format(needed)).")
                    if strength == .gap { strength = .partial }
                } else {
                    notes.append("The dates in your experience section add up to about \(format(rounded)) years; the posting asks for \(format(needed)). Other experience you haven't listed may count.")
                    if strength == .strong { strength = .partial }
                }
            } else {
                notes.append("The posting asks for \(format(needed))+ years. Add dates to your experience so this can be checked.")
            }
        }
        // Degrees.
        if let degree = requiredDegree(in: text) {
            let edu = profile.sections.filter { $0.kind == .education || $0.kind == .certifications }.flatMap { $0.entries }
            let hit = edu.first { e in degreeLevel(of: e.title + " " + e.details) >= degree.level }
            if let hit {
                notes.append("Your education lists “\(hit.headline)”.")
                if let unit = units.first(where: { $0.ref.entryID == hit.id && $0.ref.field == .entryTitle }),
                   !evidence.contains(where: { $0.unit == unit }) {
                    evidence.insert(Evidence(unit: unit, sharedTerms: [degree.name], score: 1), at: 0)
                }
                if strength != .strong && (text.split(separator: " ").count <= 14 || strength == .partial) { strength = .strong }
                else if strength == .gap { strength = .partial }
            } else if !edu.isEmpty {
                notes.append("No \(degree.name) was found in your education section.")
            }
        }

        let covered = Set(evidence.flatMap { $0.sharedTerms })
        let missing = reqTerms.subtracting(covered)
            .filter { $0.count > 3 && !$0.allSatisfy({ $0.isNumber }) }
            .sorted { a, b in a.contains(" ") != b.contains(" ") ? a.contains(" ") : a < b }
        // Show words as the posting wrote them, and skip single words already inside a phrase.
        let phrases = missing.filter { $0.contains(" ") }
        let readable = Tailor.readable(missing, in: text).filter { word in
            word.contains(" ") || !phrases.contains { $0.contains(word.lowercased()) || $0.contains(TextTools.stem(word.lowercased())) }
        }
        return RequirementMatch(id: id, text: text, kind: kind, strength: strength, evidence: evidence, notes: notes,
                                missingTerms: Array(readable.prefix(6)))
    }

    static func question(for r: RequirementMatch) -> String {
        let l = r.text.lowercased()
        if requiredYears(in: r.text) != nil {
            return "The posting asks: “\(r.text)”. How many years of this kind of work have you done, and in which roles?"
        }
        if requiredDegree(in: r.text) != nil || l.contains("certif") || l.contains("license") {
            return "The posting asks: “\(r.text)”. Do you hold this credential (or one close to it)? If so, add it to your profile."
        }
        return "Your profile doesn't mention: “\(r.text)”. Have you done this? If yes, describe where and what you did; if not, leave it as a gap."
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Years and degrees

    static let yearsPattern = Rx("(\\d{1,2})(?:\\s*(?:-|–|to)\\s*\\d{1,2})?\\s*\\+?\\s*(?:or more\\s+)?years?")
    static let wordYears: [String: Double] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                              "eight": 8, "nine": 9, "ten": 10]

    public static func requiredYears(in text: String) -> Double? {
        let l = text.lowercased()
        guard l.contains("year") else { return nil }
        if let m = yearsPattern.firstMatch(l), let v = Double(m[1]), v > 0, v < 40 { return v }
        for (word, v) in wordYears where l.contains("\(word) years") || l.contains("\(word) (\(Int(v))) years") || l.contains("\(word)+ years") {
            return v
        }
        return nil
    }

    struct Degree { var level: Int; var name: String }

    static func requiredDegree(in text: String) -> Degree? {
        let l = " " + text.lowercased() + " "
        if l.contains("phd") || l.contains("ph.d") || l.contains("doctorate") || l.contains("doctoral") { return Degree(level: 4, name: "doctorate") }
        if l.contains("master") || l.contains(" m.ed") || l.contains(" m.a.") || l.contains(" m.s.") || l.contains("graduate degree") {
            return Degree(level: 3, name: "master's degree")
        }
        if l.contains("bachelor") || l.contains(" b.a.") || l.contains(" b.s.") || l.contains(" ba ") || l.contains(" bs ")
            || l.contains("four-year degree") || l.contains("4-year degree") || l.contains("undergraduate degree")
            || l.contains("college degree") || l.contains("university degree") {
            return Degree(level: 2, name: "bachelor's degree")
        }
        if l.contains("associate's degree") || l.contains("associate degree") { return Degree(level: 1, name: "associate degree") }
        return nil
    }

    static func degreeLevel(of text: String) -> Int {
        let l = " " + text.lowercased().replacingOccurrences(of: ",", with: " ") + " "
        if l.contains("phd") || l.contains("ph.d") || l.contains("ed.d") || l.contains("doctor") { return 4 }
        if l.contains("master") || l.contains(" m.ed") || l.contains(" med ") || l.contains(" m.a") || l.contains(" ma ")
            || l.contains(" m.s") || l.contains(" ms ") || l.contains(" mba") || l.contains(" mat ") || l.contains(" m.a.t") { return 3 }
        if l.contains("bachelor") || l.contains(" b.a") || l.contains(" ba ") || l.contains(" b.s") || l.contains(" bs ")
            || l.contains(" bfa") || l.contains(" b.f.a") || l.contains(" bba") { return 2 }
        if l.contains("associate") || l.contains(" a.a") || l.contains(" a.s") { return 1 }
        return 0
    }

    /// Total years covered by experience entries (overlapping roles counted once).
    public static func experienceYears(_ profile: Profile, now: Date = Date()) -> Double? {
        var intervals: [(Double, Double)] = []
        for s in profile.sections where s.kind == .experience {
            for e in s.entries where !e.hidden {
                guard let start = decimalYear(e.startDate, now: now, isEnd: false) else { continue }
                let end = decimalYear(e.endDate, now: now, isEnd: true) ?? start + 1.0 / 12
                if end >= start { intervals.append((start, end)) }
            }
        }
        guard !intervals.isEmpty else { return nil }
        intervals.sort { $0.0 < $1.0 }
        var total = 0.0
        var cur = intervals[0]
        for iv in intervals.dropFirst() {
            if iv.0 <= cur.1 { cur.1 = max(cur.1, iv.1) } else { total += cur.1 - cur.0; cur = iv }
        }
        total += cur.1 - cur.0
        return total
    }

    static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10,
                         "nov": 11, "dec": 12, "spr": 3, "sum": 6, "fal": 9, "aut": 9, "win": 1]

    /// "Mar 2019" → 2019.17. "Present" → now. Year-only end dates count to the end of that year.
    static func decimalYear(_ s: String, now: Date, isEnd: Bool) -> Double? {
        let l = s.lowercased().trimmed
        if l.isEmpty { return nil }
        if ["present", "current", "now", "today", "ongoing"].contains(where: { l.contains($0) }) {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
            return Double(c.year ?? 2000) + Double((c.month ?? 1) - 1) / 12 + (1.0 / 12)
        }
        guard let ym = Rx("((?:19|20)\\d{2})").firstMatch(l), let year = Double(ym[1]) else { return nil }
        var month: Int?
        if let mm = Rx("^(\\d{1,2})/").firstMatch(l), let m = Int(mm[1]), (1...12).contains(m) { month = m }
        for (k, v) in months where l.hasPrefix(k) { month = v }
        if let month { return year + Double(month - 1) / 12 + (isEnd ? 1.0 / 12 : 0) }
        return year + (isEnd ? 1 : 0)
    }
}
