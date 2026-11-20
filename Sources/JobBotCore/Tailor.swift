import Foundation

/// Suggests changes to a tailored resume for one job. Every suggestion only rearranges, reuses
/// or rewords what the profile already says, and carries the evidence for it.
public enum Tailor {
    /// Phrasings that mean exactly the same thing, safe to swap for the posting's wording.
    /// (Abbreviations are expanded rather than replaced: "English Language Arts (ELA)".)
    public static let swapGroups: [[String]] = [
        ["English Language Arts", "ELA"],
        ["item writing", "item authoring", "item development"],
        ["assessment development", "test development"],
        ["standards alignment", "alignment to standards"],
        ["quality assurance", "QA"],
        ["subject matter experts", "SMEs"],
        ["subject matter expert", "SME"],
        ["learning management system", "LMS"],
        ["Universal Design for Learning", "UDL"],
        ["English learners", "English language learners"],
        ["copyediting", "copy editing"],
        ["K-12", "K–12", "K12"],
        ["Common Core State Standards", "CCSS"],
    ]

    struct JobTerms {
        var weights: [String: Double] = [:]
        var lines: [String] = []

        func score(_ text: String) -> (Double, [String]) {
            let t = TextTools.terms(text)
            var s = 0.0
            var hits: [String] = []
            for term in t {
                if let w = weights[term] {
                    s += w * (term.contains(" ") ? 1.5 : 1)
                    hits.append(term)
                }
            }
            return (s, hits.sorted())
        }

        func linesMentioning(_ terms: [String], limit: Int = 2) -> [String] {
            guard !terms.isEmpty else { return [] }
            var out: [String] = []
            for l in lines {
                let lt = TextTools.terms(l)
                if terms.contains(where: { lt.contains($0) }) { out.append(l) }
                if out.count >= limit { break }
            }
            return out
        }
    }

    static func jobTerms(_ job: Job) -> JobTerms {
        var jt = JobTerms()
        func add(_ items: [String], _ w: Double) {
            for item in items {
                for t in TextTools.terms(item) { jt.weights[t, default: 0] += w }
                jt.lines.append(item)
            }
        }
        add(job.parsed.requiredQualifications, 3)
        add(job.parsed.responsibilities, 2)
        add(job.parsed.preferredQualifications, 1)
        for k in job.parsed.keywords {
            for t in TextTools.terms(k) { jt.weights[t, default: 0] += 2 }
        }
        if jt.lines.isEmpty {
            add(TextTools.sentences(job.descriptionText), 1)
        }
        return jt
    }

    public static func suggestions(for resume: Profile, job: Job, report: MatchReport? = nil) -> [Suggestion] {
        let jt = jobTerms(job)
        let units = resume.units(includeHidden: false)
        var out: [Suggestion] = []
        out.append(contentsOf: summarySuggestions(resume, jt: jt, units: units))
        out.append(contentsOf: bulletOrderSuggestions(resume, jt: jt, units: units))
        out.append(contentsOf: skillSuggestions(resume, job: job, jt: jt, units: units))
        out.append(contentsOf: termSuggestions(resume, job: job, units: units))
        out.append(contentsOf: trimSuggestions(resume, jt: jt, units: units))
        return out
    }

    // MARK: Summary

    static func summarySuggestions(_ p: Profile, jt: JobTerms, units: [ProfileUnit]) -> [Suggestion] {
        let sentences = TextTools.sentences(p.summary)
        guard sentences.count >= 2 else { return [] }
        let scored = sentences.enumerated().map { (i, s) -> (Int, String, Double, [String]) in
            let (score, hits) = jt.score(s)
            return (i, s, score, hits)
        }
        let reordered = scored.sorted { a, b in a.2 != b.2 ? a.2 > b.2 : a.0 < b.0 }
        guard reordered.map({ $0.0 }) != scored.map({ $0.0 }), let top = reordered.first, top.2 > 0 else { return [] }
        let after = reordered.map { $0.1 }.joined(separator: " ")
        let summaryUnit = units.filter { $0.ref.field == .summary }
        return [Suggestion(kind: .rewriteSummary, title: "Lead the summary with what this job emphasizes",
                           explanation: "Moves the sentence that mentions \(list(readable(top.3, in: top.1))) to the front. Recruiters often skim only the first line. The wording is unchanged.",
                           before: p.summary, after: after, target: EvidenceRef(field: .summary),
                           jobEvidence: jt.linesMentioning(top.3), profileEvidence: summaryUnit)]
    }

    // MARK: Bullet order

    static func bulletOrderSuggestions(_ p: Profile, jt: JobTerms, units: [ProfileUnit]) -> [Suggestion] {
        var out: [Suggestion] = []
        for s in p.sections where !s.hidden && (s.kind == .experience || s.kind == .volunteer || s.kind == .projects) {
            for e in s.entries where !e.hidden && e.bullets.count >= 2 {
                let scored = e.bullets.enumerated().map { (i, b) -> (Int, Bullet, Double, [String]) in
                    let (score, hits) = jt.score(b.text)
                    return (i, b, score, hits)
                }
                let reordered = scored.sorted { a, b in a.2 != b.2 ? a.2 > b.2 : a.0 < b.0 }
                guard reordered.map({ $0.0 }) != scored.map({ $0.0 }), let top = reordered.first, top.2 > 0 else { continue }
                // Only worth suggesting when the first bullet would change.
                guard top.0 != 0 else { continue }
                let before = e.bullets.map { "• " + $0.text }.joined(separator: "\n")
                let after = reordered.map { "• " + $0.1.text }.joined(separator: "\n")
                let evidence = units.filter { u in reordered.prefix(2).contains { $0.1.id == u.ref.bulletID } }
                let hits = Array(Set(reordered.prefix(2).flatMap { $0.3 })).sorted()
                let topText = reordered.prefix(2).map { $0.1.text }.joined(separator: " ")
                let shownHits = list(readable(hits, in: topText))
                out.append(Suggestion(kind: .reorderBullets,
                                      title: "Reorder bullets for \(e.headline.isEmpty ? s.title : e.headline)",
                                      explanation: "Puts the bullets that mention \(shownHits) first in this role, where readers and screening software look first. No wording changes.",
                                      before: before, after: after,
                                      target: EvidenceRef(field: .bullet, sectionID: s.id, entryID: e.id),
                                      jobEvidence: jt.linesMentioning(hits), profileEvidence: evidence,
                                      newOrder: reordered.map { $0.1.id.uuidString }))
            }
        }
        return out
    }

    // MARK: Skills

    static func skillSuggestions(_ p: Profile, job: Job, jt: JobTerms, units: [ProfileUnit]) -> [Suggestion] {
        guard let skills = p.sections.first(where: { $0.kind == .skills && !$0.hidden }) else { return [] }
        var out: [Suggestion] = []
        let items = skills.items.filter { !$0.trimmed.isEmpty }

        // Order
        if items.count >= 3 {
            let scored = items.enumerated().map { (i, s) -> (Int, String, Double) in (i, s, jt.score(s).0) }
            let reordered = scored.sorted { a, b in a.2 != b.2 ? a.2 > b.2 : a.0 < b.0 }
            if reordered.map({ $0.0 }) != scored.map({ $0.0 }), (reordered.first?.2 ?? 0) > 0 {
                let moved = reordered.filter { $0.2 > 0 }.map { $0.1 }
                out.append(Suggestion(kind: .reorderSkills, title: "List the matching skills first",
                                      explanation: "Moves \(list(Array(moved.prefix(4)))) to the front of your skills list because the posting asks for them.",
                                      before: items.joined(separator: ", "), after: reordered.map { $0.1 }.joined(separator: ", "),
                                      target: EvidenceRef(field: .skill, sectionID: skills.id),
                                      jobEvidence: jt.linesMentioning(Array(TextTools.terms(moved.joined(separator: " "))).sorted()),
                                      profileEvidence: units.filter { $0.ref.field == .skill && moved.contains($0.text) },
                                      newOrder: reordered.map { $0.1 }))
            }
        }

        // Add keywords the profile already shows elsewhere.
        let skillsText = " " + TextTools.words(items.joined(separator: " , ")).joined(separator: " ") + " "
        let skillTerms = TextTools.terms(items.joined(separator: " "))
        var added = 0
        for keyword in job.parsed.keywords {
            if added >= 8 { break }
            let k = TextTools.words(keyword).joined(separator: " ")
            guard k.count >= 2 else { continue }
            if skillsText.contains(" " + k + " ") { continue }
            let kTerms = TextTools.terms(keyword)
            if !kTerms.isEmpty && kTerms.isSubset(of: skillTerms) { continue }
            // Evidence: a bullet, summary or note that contains the keyword (or its equivalent).
            let support = units.filter { u in
                guard u.ref.field != .skill && u.ref.field != .entryTitle else { return false }
                let words = " " + TextTools.words(u.text).joined(separator: " ") + " "
                if words.contains(" " + k + " ") { return true }
                if let canon = TextTools.canonical[k] { return TextTools.phrases(in: u.text).contains(canon) }
                return false
            }
            guard !support.isEmpty else { continue }
            let display = keyword.first?.isLowercase == true && keyword.uppercased() != keyword ? keyword.capitalizedFirst : keyword
            out.append(Suggestion(kind: .addSkill, title: "Add “\(display)” to Skills",
                                  explanation: "The posting lists \(display), and your experience already shows it (see the evidence). Listing it in Skills helps keyword searches find it.",
                                  before: "", after: display, target: EvidenceRef(field: .skill, sectionID: skills.id),
                                  jobEvidence: jt.linesMentioning(Array(kTerms)), profileEvidence: Array(support.prefix(3))))
            added += 1
        }
        return out
    }

    // MARK: Wording

    static func termSuggestions(_ p: Profile, job: Job, units: [ProfileUnit]) -> [Suggestion] {
        var out: [Suggestion] = []
        var jobLines: [String] = [job.descriptionText]
        jobLines.append(contentsOf: job.parsed.requiredQualifications)
        jobLines.append(contentsOf: job.parsed.responsibilities)
        jobLines.append(contentsOf: job.parsed.preferredQualifications)
        let jobText = jobLines.joined(separator: "\n")
        let jobWords = " " + TextTools.words(jobText).joined(separator: " ") + " "
        for group in swapGroups {
            // The posting's form: the first group member it uses.
            guard let jobForm = group.first(where: { jobWords.contains(" " + TextTools.words($0).joined(separator: " ") + " ") }) else { continue }
            let jobKey = " " + TextTools.words(jobForm).joined(separator: " ") + " "
            for u in units where u.ref.field == .bullet || u.ref.field == .summary || u.ref.field == .headline {
                let unitWords = " " + TextTools.words(u.text).joined(separator: " ") + " "
                if unitWords.contains(jobKey) { continue }
                guard let profileForm = group.first(where: { $0 != jobForm && unitWords.contains(" " + TextTools.words($0).joined(separator: " ") + " ") }),
                      let range = wordRange(of: profileForm, in: u.text) else { continue }
                let found = String(u.text[range])
                let replacement: String
                if isAbbreviation(jobForm) && !isAbbreviation(found) {
                    replacement = "\(found) (\(jobForm))"
                } else if isAbbreviation(found) && !isAbbreviation(jobForm) {
                    replacement = "\(matchCase(jobForm, like: found)) (\(found))"
                } else {
                    replacement = matchCase(jobForm, like: found)
                }
                var after = u.text
                after.replaceSubrange(range, with: replacement)
                out.append(Suggestion(kind: .alignTerm, title: "Use the posting's term “\(jobForm)”",
                                      explanation: "The posting says “\(jobForm)” and your \(u.ref.field == .summary ? "summary" : "bullet") says “\(found)”, which means the same thing. Using the posting's wording can help keyword matching.",
                                      before: u.text, after: after, target: u.ref,
                                      jobEvidence: [firstLine(containing: jobForm, in: job)].compactMap { $0 },
                                      profileEvidence: [u]))
            }
        }
        return out
    }

    /// The first whole-word occurrence ("ELA" in "ELA items", not inside "related").
    static func wordRange(of phrase: String, in text: String) -> Range<String.Index>? {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
        return Rx(pattern).ranges(text).first
    }

    static func isAbbreviation(_ s: String) -> Bool {
        s.count <= 5 && s.filter({ $0.isLetter }).allSatisfy { $0.isUppercase } && s.contains(where: { $0.isLetter })
    }

    static func matchCase(_ s: String, like model: String) -> String {
        if isAbbreviation(s) { return s }
        if model.first?.isUppercase == true { return s.capitalizedFirst }
        if s.filter({ $0.isUppercase }).count > 1 { return s } // proper names like "English Language Arts"
        return s.lowercased()
    }

    static func firstLine(containing term: String, in job: Job) -> String? {
        var all: [String] = job.parsed.requiredQualifications
        all.append(contentsOf: job.parsed.responsibilities)
        all.append(contentsOf: job.parsed.preferredQualifications)
        all.append(contentsOf: job.parsed.other)
        return all.first { $0.range(of: term, options: .caseInsensitive) != nil }
    }

    // MARK: Trimming

    static func trimSuggestions(_ p: Profile, jt: JobTerms, units: [ProfileUnit]) -> [Suggestion] {
        let totalBullets = p.sections.filter { !$0.hidden }.flatMap { $0.entries.filter { !$0.hidden } }.reduce(0) { $0 + $1.bullets.count }
        guard totalBullets > 18 else { return [] }
        var out: [Suggestion] = []
        for s in p.sections where s.kind == .experience && !s.hidden {
            for e in s.entries.filter({ !$0.hidden }).dropFirst(2) {
                for b in e.bullets where jt.score(b.text).0 == 0 {
                    out.append(Suggestion(kind: .hideBullet, title: "Optional: leave out a less related bullet",
                                          explanation: "Your resume has \(totalBullets) bullets. This one, from an earlier role, doesn't touch anything the posting mentions. Leaving it out of this version keeps the page focused. It stays in your master resume.",
                                          before: b.text, after: "",
                                          target: EvidenceRef(field: .bullet, sectionID: s.id, entryID: e.id, bulletID: b.id),
                                          profileEvidence: units.filter { $0.ref.bulletID == b.id }))
                    if out.count >= 4 { return out }
                }
            }
        }
        return out
    }

    // MARK: Applying

    public enum ApplyError: Error, LocalizedError {
        case targetMissing
        case changedSince
        case empty

        public var errorDescription: String? {
            switch self {
            case .targetMissing: return "The part of the resume this suggestion refers to is no longer there."
            case .changedSince: return "That part of the resume was edited after this suggestion was made. Refresh the suggestions."
            case .empty: return "The suggested text is empty."
            }
        }
    }

    public static func apply(_ s: Suggestion, to p: inout Profile) throws {
        switch s.kind {
        case .reorderBullets:
            guard let si = p.sections.firstIndex(where: { $0.id == s.target.sectionID }),
                  let ei = p.sections[si].entries.firstIndex(where: { $0.id == s.target.entryID }) else { throw ApplyError.targetMissing }
            var bullets = p.sections[si].entries[ei].bullets
            let current = bullets.map { $0.id.uuidString }
            guard Set(current) == Set(s.newOrder) else { throw ApplyError.changedSince }
            bullets.sort { (s.newOrder.firstIndex(of: $0.id.uuidString) ?? 0) < (s.newOrder.firstIndex(of: $1.id.uuidString) ?? 0) }
            p.sections[si].entries[ei].bullets = bullets
        case .reorderSkills:
            guard let si = p.sections.firstIndex(where: { $0.id == s.target.sectionID }) else { throw ApplyError.targetMissing }
            let items = p.sections[si].items.filter { !$0.trimmed.isEmpty }
            guard Set(items) == Set(s.newOrder) else { throw ApplyError.changedSince }
            p.sections[si].items = s.newOrder
        case .addSkill:
            guard let si = p.sections.firstIndex(where: { $0.id == s.target.sectionID }) else { throw ApplyError.targetMissing }
            let value = s.after.trimmed
            guard !value.isEmpty else { throw ApplyError.empty }
            if !p.sections[si].items.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                p.sections[si].items.append(value)
            }
        case .alignTerm, .rewriteBullet, .rewriteSummary:
            let value = WritingRules.clean(s.after)
            guard !value.isEmpty else { throw ApplyError.empty }
            try replaceText(at: s.target, before: s.before, with: value, in: &p)
        case .hideBullet:
            guard let si = p.sections.firstIndex(where: { $0.id == s.target.sectionID }),
                  let ei = p.sections[si].entries.firstIndex(where: { $0.id == s.target.entryID }) else { throw ApplyError.targetMissing }
            guard let bi = p.sections[si].entries[ei].bullets.firstIndex(where: { $0.id == s.target.bulletID }) else { throw ApplyError.targetMissing }
            p.sections[si].entries[ei].bullets.remove(at: bi)
        }
    }

    static func replaceText(at ref: EvidenceRef, before: String, with value: String, in p: inout Profile) throws {
        switch ref.field {
        case .summary:
            guard p.summary.trimmed == before.trimmed else { throw ApplyError.changedSince }
            p.summary = value
        case .headline:
            guard p.headline.trimmed == before.trimmed else { throw ApplyError.changedSince }
            p.headline = value
        case .bullet:
            guard let si = p.sections.firstIndex(where: { $0.id == ref.sectionID }),
                  let ei = p.sections[si].entries.firstIndex(where: { $0.id == ref.entryID }),
                  let bi = p.sections[si].entries[ei].bullets.firstIndex(where: { $0.id == ref.bulletID }) else { throw ApplyError.targetMissing }
            guard p.sections[si].entries[ei].bullets[bi].text.trimmed == before.trimmed else { throw ApplyError.changedSince }
            p.sections[si].entries[ei].bullets[bi].text = value
        case .entryDetails:
            guard let si = p.sections.firstIndex(where: { $0.id == ref.sectionID }),
                  let ei = p.sections[si].entries.firstIndex(where: { $0.id == ref.entryID }) else { throw ApplyError.targetMissing }
            guard p.sections[si].entries[ei].details.trimmed == before.trimmed else { throw ApplyError.changedSince }
            p.sections[si].entries[ei].details = value
        default:
            throw ApplyError.targetMissing
        }
    }

    /// Turns matched terms (stems like "assess") back into words from the text ("assessments").
    static func readable(_ terms: [String], in text: String) -> [String] {
        let words = TextTools.words(text)
        var out: [String] = []
        for t in terms {
            let shown: String
            if t.contains(" ") {
                shown = t
            } else if let w = words.first(where: { TextTools.stem($0) == t }) {
                shown = w
            } else {
                shown = t
            }
            if !out.contains(shown) { out.append(shown) }
        }
        return out
    }

    /// "a, b and c"
    static func list(_ items: [String]) -> String {
        let shown = items.prefix(3).map { "“\($0)”" }
        switch shown.count {
        case 0: return "the posting's main terms"
        case 1: return shown[0]
        case 2: return "\(shown[0]) and \(shown[1])"
        default: return "\(shown[0]), \(shown[1]) and \(shown[2])"
        }
    }
}
