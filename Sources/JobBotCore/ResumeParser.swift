import Foundation

/// Turns resume text (from a PDF, DOCX or plain text file) into an editable profile.
///
/// It only rearranges what's in the text: nothing is added. Anything it can't place goes into an
/// "Additional Information" section and is reported, so the person can fix it.
public enum ResumeParser {
    public struct Result {
        public var profile: Profile
        public var warnings: [String]
    }

    static let headingMap: [(SectionKind?, [String])] = [
        (nil, ["summary", "professional summary", "profile", "professional profile", "about", "about me", "objective",
               "career objective", "career summary", "overview", "summary of qualifications", "qualifications summary",
               "executive summary", "personal statement"]),
        (.experience, ["experience", "work experience", "professional experience", "employment", "employment history",
                       "work history", "career history", "relevant experience", "professional history",
                       "experience highlights", "related experience", "teaching experience", "selected experience"]),
        (.education, ["education", "education and training", "education & training", "academic background",
                      "academic history", "education and certifications", "education & certifications"]),
        (.skills, ["skills", "technical skills", "core competencies", "competencies", "areas of expertise", "expertise",
                   "key skills", "skills & tools", "skills and tools", "tools", "technologies", "skills and abilities",
                   "core skills", "skills summary", "relevant skills", "software", "technical proficiencies", "proficiencies"]),
        (.certifications, ["certifications", "certification", "certificates", "licenses", "licenses and certifications",
                           "licenses & certifications", "credentials", "certifications and training",
                           "certifications & training", "training", "professional development"]),
        (.projects, ["projects", "selected projects", "key projects"]),
        (.awards, ["awards", "honors", "awards and honors", "honors and awards", "awards & honors", "recognition"]),
        (.publications, ["publications", "presentations", "publications and presentations"]),
        (.volunteer, ["volunteer", "volunteer experience", "volunteering", "community involvement", "service",
                      "leadership and service"]),
        (.other, ["additional information", "interests", "languages", "affiliations", "professional affiliations",
                  "memberships", "activities", "other"]),
    ]

    enum Heading: Equatable {
        case summary
        case section(SectionKind)
        case unknown(String)
    }

    static func heading(for line: String) -> Heading? {
        let t = line.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let key = t.lowercased().replacingOccurrences(of: "  ", with: " ").squashed
        guard !key.isEmpty, key.count <= 48 else { return nil }
        for (kind, names) in headingMap where names.contains(key) {
            if let kind { return .section(kind) }
            return .summary
        }
        // ALL-CAPS short line that isn't a known heading: treat as its own section.
        if TextTools.looksLikeHeading(line), key.split(separator: " ").count <= 5,
           !Patterns.dateRange.matches(line), !Patterns.email.matches(line), !Patterns.phone.matches(line) {
            let letters = t.filter { $0.isLetter }
            if letters.count >= 4 && letters.allSatisfy({ $0.isUppercase }) { return .unknown(t.capitalized) }
        }
        return nil
    }

    public static func parse(_ rawText: String) -> Result {
        var warnings: [String] = []
        let lines = cleanLines(rawText)
        guard !lines.isEmpty else {
            return Result(profile: .starter, warnings: ["The file didn't contain any text Job Bot could read."])
        }

        // Split into blocks under headings.
        var preamble: [String] = []
        var blocks: [(Heading, [String])] = []
        for line in lines {
            if let h = heading(for: line) {
                // An all-caps line before any known heading is usually the name, not a section.
                if case .unknown = h, blocks.isEmpty {
                    preamble.append(line)
                } else {
                    blocks.append((h, []))
                }
            } else if blocks.isEmpty {
                preamble.append(line)
            } else {
                blocks[blocks.count - 1].1.append(line)
            }
        }

        var profile = Profile()
        let header = parseHeader(preamble)
        profile.contact = header.contact
        profile.headline = header.headline
        var summaryLines = header.leftover

        for (h, body) in blocks {
            switch h {
            case .summary:
                summaryLines.append(contentsOf: body)
            case .section(let kind):
                if let i = profile.sections.firstIndex(where: { $0.kind == kind && kind != .other }) {
                    profile.sections[i] = merge(profile.sections[i], with: parseSection(kind: kind, title: nil, lines: body))
                } else {
                    profile.sections.append(parseSection(kind: kind, title: nil, lines: body))
                }
            case .unknown(let title):
                profile.sections.append(parseSection(kind: .other, title: title, lines: body))
            }
        }
        profile.summary = joinParagraph(summaryLines.map { TextTools.bulletText($0) ?? $0 })

        if blocks.isEmpty {
            warnings.append("Job Bot couldn't find section headings such as Experience or Education. Everything after your contact details was placed in the summary. Move it into sections before tailoring.")
        }
        for kind in [SectionKind.experience, .education, .skills] where !profile.sections.contains(where: { $0.kind == kind }) {
            profile.sections.append(ResumeSection(kind: kind))
            if !blocks.isEmpty { warnings.append("No \(kind.defaultTitle) section was found. An empty one was added so you can fill it in.") }
        }
        if profile.contact.name.isEmpty { warnings.append("Your name wasn't found at the top of the resume. Add it under Contact.") }
        if profile.contact.email.isEmpty { warnings.append("No email address was found. Add one under Contact if you want it on your resume.") }
        for s in profile.sections where s.kind == .experience {
            for e in s.entries where e.dateRange.isEmpty {
                warnings.append("No dates were found for “\(e.headline.isEmpty ? "an experience entry" : e.headline)”. Add them if you want them shown.")
            }
        }
        profile.sections.sort { order($0.kind) < order($1.kind) }
        return Result(profile: profile, warnings: warnings)
    }

    static func order(_ k: SectionKind) -> Int {
        switch k {
        case .experience: return 0
        case .education: return 1
        case .skills: return 2
        case .certifications: return 3
        case .projects: return 4
        case .publications: return 5
        case .awards: return 6
        case .volunteer: return 7
        case .other: return 8
        }
    }

    // MARK: Lines

    /// Splits text into trimmed lines, joining lines that were wrapped mid-sentence.
    static func cleanLines(_ text: String, joinWrappedBullets: Bool = true) -> [String] {
        let raw = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .components(separatedBy: "\n")
        var out: [String] = []
        for var line in raw {
            line = line.replacingOccurrences(of: "\t", with: "    ").trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // A lone bullet character on its own line: the text follows on the next line.
            if line.count == 1, TextTools.bulletMarkers.contains(line.first!) {
                out.append(line)
                continue
            }
            if let last = out.last, last.count == 1, TextTools.bulletMarkers.contains(last.first!) {
                out[out.count - 1] = "• " + line
                continue
            }
            if let last = out.last, isContinuation(line, after: last, joinWrappedBullets: joinWrappedBullets) {
                if last.hasSuffix("-") && !last.hasSuffix(" -") {
                    out[out.count - 1] = String(last.dropLast()) + line
                } else {
                    out[out.count - 1] = last + " " + line
                }
                continue
            }
            out.append(line)
        }
        return out
    }

    /// A wrapped line: starts in lowercase (or with a closing bracket) and follows a line that
    /// didn't end a sentence.
    static func isContinuation(_ line: String, after previous: String, joinWrappedBullets: Bool = true) -> Bool {
        guard let first = line.first else { return false }
        if TextTools.bulletText(line) != nil || heading(for: line) != nil { return false }
        let prevEnds = previous.hasSuffix(".") || previous.hasSuffix(":") || previous.hasSuffix(";")
        if prevEnds { return false }
        if heading(for: previous) != nil { return false }
        if first.isLowercase || first == ")" || first == "&" { return true }
        // A long bullet wrapped onto a line that starts with a capital ("ELA items for…"), as PDF
        // text often does. Short lines that look like a job title or employer start a new entry.
        if joinWrappedBullets, TextTools.bulletText(previous) != nil, previous.count >= 70, !Patterns.dateRange.matches(line),
           !line.hasSuffix(":") {
            let words = line.split(separator: " ").count
            let looksLikeHeader = words <= 6 && (looksLikeTitle(line, kind: .experience) || looksLikeOrganization(line)
                                                 || looksLikeTitle(line, kind: .education))
            if !looksLikeHeader && !Patterns.email.matches(line) { return true }
        }
        if previous.hasSuffix(",") || previous.hasSuffix(" and") || previous.hasSuffix(" of") || previous.hasSuffix(" the")
            || previous.hasSuffix(" to") || previous.hasSuffix(" for") || previous.hasSuffix(" with") || previous.hasSuffix(" in") {
            return TextTools.bulletText(previous) != nil
        }
        return false
    }

    static func joinParagraph(_ lines: [String]) -> String {
        lines.map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: " ").squashed
    }

    // MARK: Header (name and contact details)

    struct Header {
        var contact = ContactInfo()
        var headline = ""
        var leftover: [String] = []
    }

    static func parseHeader(_ lines: [String]) -> Header {
        var h = Header()
        for line in lines {
            var rest = line
            for m in Patterns.email.allMatches(rest) where h.contact.email.isEmpty {
                h.contact.email = m[0]
            }
            rest = Patterns.email.replace(rest, with: " ")
            for m in Patterns.url.allMatches(rest) {
                let link = m[0].trimmingCharacters(in: CharacterSet(charactersIn: ".;)("))
                if !h.contact.links.contains(link) { h.contact.links.append(link) }
            }
            rest = Patterns.url.replace(rest, with: " ")
            if let m = Patterns.phone.firstMatch(rest), h.contact.phone.isEmpty {
                h.contact.phone = m[0].trimmed
            }
            rest = Patterns.phone.replace(rest, with: " ")
            if h.contact.location.isEmpty, let m = Patterns.cityState.firstMatch(rest) {
                h.contact.location = m[0]
                rest = rest.replacingOccurrences(of: m[0], with: " ")
            }
            let pieces = rest.components(separatedBy: CharacterSet(charactersIn: "|•·,"))
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
            let leftover = pieces.joined(separator: " ").squashed
            guard !leftover.isEmpty else { continue }
            if h.contact.name.isEmpty, looksLikeName(leftover) {
                let letters = leftover.filter { $0.isLetter }
                h.contact.name = letters.count > 3 && letters.allSatisfy({ $0.isUppercase }) ? leftover.capitalized : leftover
            } else if h.headline.isEmpty, leftover.split(separator: " ").count <= 10, !leftover.hasSuffix(".") {
                h.headline = pieces.joined(separator: " | ")
            } else if h.contact.location.isEmpty, leftover.lowercased() == "remote" {
                h.contact.location = "Remote"
            } else {
                h.leftover.append(line)
            }
        }
        return h
    }

    static func looksLikeName(_ s: String) -> Bool {
        let words = s.split(separator: " ")
        guard (1...5).contains(words.count), s.count <= 40 else { return false }
        guard !s.contains(where: { $0.isNumber }) else { return false }
        let titleWords = ["specialist", "developer", "manager", "writer", "editor", "designer", "teacher", "consultant",
                          "director", "coordinator", "analyst", "resume", "curriculum", "vitae"]
        let lower = s.lowercased()
        if titleWords.contains(where: { lower.contains($0) }) { return false }
        return words.allSatisfy { w in
            guard let f = w.first else { return false }
            return f.isUppercase || w.count <= 3
        }
    }

    // MARK: Sections

    static func merge(_ a: ResumeSection, with b: ResumeSection) -> ResumeSection {
        var s = a
        s.entries.append(contentsOf: b.entries)
        s.items.append(contentsOf: b.items.filter { !s.items.contains($0) })
        return s
    }

    static func parseSection(kind: SectionKind, title: String?, lines: [String]) -> ResumeSection {
        switch kind {
        case .skills:
            return ResumeSection(kind: .skills, title: title, items: parseList(lines))
        case .certifications, .awards:
            return ResumeSection(kind: kind, title: title, entries: lines.map { parseSimpleEntry($0) })
        case .other:
            var e = ResumeEntry()
            e.bullets = lines.map { Bullet(text: TextTools.bulletText($0) ?? $0) }
            return ResumeSection(kind: .other, title: title, entries: lines.isEmpty ? [] : [e])
        default:
            return ResumeSection(kind: kind, title: title, entries: parseEntries(lines, kind: kind))
        }
    }

    /// Skills: split on commas, bullets, pipes and semicolons; "Label: a, b" keeps a and b.
    static func parseList(_ lines: [String]) -> [String] {
        var items: [String] = []
        for line in lines {
            var text = TextTools.bulletText(line) ?? line
            if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) < 40 {
                text = String(text[text.index(after: colon)...])
            }
            let parts = text.components(separatedBy: CharacterSet(charactersIn: ",;|•·▪●"))
                .flatMap { $0.components(separatedBy: "    ") }
                .map { $0.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !$0.isEmpty }
            for p in parts where !items.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) {
                items.append(p)
            }
        }
        return items
    }

    static func parseSimpleEntry(_ line: String) -> ResumeEntry {
        var text = TextTools.bulletText(line) ?? line
        var e = ResumeEntry()
        if let m = Patterns.dateRange.firstMatch(text) {
            e.startDate = m[1].trimmed
            e.endDate = m[2].trimmed.capitalizedFirst
            text = text.replacingOccurrences(of: m[0], with: " ")
        } else if let m = Patterns.singleDate.firstMatch(text) {
            e.endDate = m[1].trimmed
            text = text.replacingOccurrences(of: m[0], with: " ")
        }
        let parts = splitHeader(cleanSeparators(text), commas: false)
        e.title = parts.first ?? ""
        if parts.count > 1 { e.organization = parts[1...].joined(separator: ", ") }
        return e
    }

    /// Experience, education, projects: a header (title, employer, dates) followed by bullets.
    static func parseEntries(_ lines: [String], kind: SectionKind) -> [ResumeEntry] {
        var entries: [ResumeEntry] = []
        var headerLines: [String] = []
        var bullets: [String] = []
        var details: [String] = []

        func finish() {
            guard !headerLines.isEmpty || !bullets.isEmpty || !details.isEmpty else { return }
            var e = buildHeader(headerLines, kind: kind)
            e.bullets = bullets.map { Bullet(text: $0) }
            e.details = joinParagraph(details)
            entries.append(e)
            headerLines = []
            bullets = []
            details = []
        }

        for line in lines {
            if let b = TextTools.bulletText(line) {
                if headerLines.isEmpty && bullets.isEmpty && !entries.isEmpty && details.isEmpty {
                    // Bullets right after a finished entry belong to it.
                    entries[entries.count - 1].bullets.append(Bullet(text: b))
                } else {
                    bullets.append(b)
                }
                continue
            }
            let hasDates = Patterns.dateRange.matches(line) || (kind == .education && Patterns.singleDate.matches(line))
            let wordCount = line.split(separator: " ").count
            let sentenceLike = line.hasSuffix(".") || wordCount > 14
            if sentenceLike && !hasDates {
                // A sentence: a bullet without a marker, or a description.
                if !headerLines.isEmpty || !entries.isEmpty {
                    if kind == .education { details.append(line) } else { bullets.append(line) }
                } else {
                    details.append(line)
                }
                continue
            }
            // A short line: part of a header. A new header starts once the current entry has
            // bullets, or when the header already has dates and this line has dates too.
            let currentHasDates = headerLines.contains { Patterns.dateRange.matches($0) || (kind == .education && Patterns.singleDate.matches($0)) }
            if !bullets.isEmpty || !details.isEmpty || (hasDates && currentHasDates) || headerLines.count >= 3 {
                finish()
            }
            headerLines.append(line)
        }
        finish()
        return entries
    }

    static func buildHeader(_ lines: [String], kind: SectionKind) -> ResumeEntry {
        var e = ResumeEntry()
        var texts: [String] = []
        for line in lines {
            var t = line
            if e.startDate.isEmpty && e.endDate.isEmpty, let m = Patterns.dateRange.firstMatch(t) {
                e.startDate = m[1].trimmed
                e.endDate = m[2].trimmed.capitalizedFirst
                t = t.replacingOccurrences(of: m[0], with: " ")
            } else if e.startDate.isEmpty && e.endDate.isEmpty, kind == .education, let m = Patterns.singleDate.firstMatch(t) {
                e.endDate = m[1].trimmed
                t = t.replacingOccurrences(of: m[0], with: " ")
            }
            if e.location.isEmpty, let m = Patterns.cityState.firstMatch(t) {
                e.location = m[0]
                t = t.replacingOccurrences(of: m[0], with: " ")
            } else if e.location.isEmpty, let r = t.range(of: "(Remote)", options: .caseInsensitive) ?? t.range(of: " Remote", options: [.caseInsensitive, .backwards]) {
                e.location = "Remote"
                t.removeSubrange(r)
            }
            texts.append(contentsOf: splitHeader(cleanSeparators(t)))
        }
        texts = texts.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return e }
        if texts.count == 1 {
            if kind == .education || looksLikeTitle(texts[0], kind: kind) || !looksLikeOrganization(texts[0]) {
                e.title = texts[0]
            } else {
                e.organization = texts[0]
            }
            return e
        }
        if kind == .education {
            // School is the piece that looks like an institution; the rest describes the degree.
            if let schoolIndex = texts.firstIndex(where: { looksLikeOrganization($0) && !looksLikeTitle($0, kind: .education) }) {
                e.organization = texts[schoolIndex]
                var others = texts
                others.remove(at: schoolIndex)
                e.title = others.joined(separator: ", ")
            } else {
                e.title = texts[0]
                e.organization = texts.dropFirst().joined(separator: ", ")
            }
            return e
        }
        // Decide which piece is the title and which is the organization.
        let a = texts[0], b = texts[1]
        let aIsOrg = looksLikeOrganization(a) && !looksLikeTitle(a, kind: kind)
        let bIsTitle = looksLikeTitle(b, kind: kind) && !looksLikeOrganization(b)
        if aIsOrg || (bIsTitle && !looksLikeTitle(a, kind: kind)) {
            e.organization = a
            e.title = b
        } else {
            e.title = a
            e.organization = b
        }
        let rest = texts.dropFirst(2).filter { !$0.isEmpty }
        if !rest.isEmpty {
            if e.location.isEmpty && rest.count == 1 && rest[rest.startIndex].split(separator: " ").count <= 3 {
                e.location = rest[rest.startIndex]
            } else {
                e.details = rest.joined(separator: ", ")
            }
        }
        return e
    }

    /// Removes leftover separators and parentheses from a header line after dates were cut out.
    static func cleanSeparators(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "()", with: " ").replacingOccurrences(of: "( )", with: " ")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " |,–—-•·:()"))
        return t.squashed
    }

    /// "Assessment Specialist | Pearson" → ["Assessment Specialist", "Pearson"]. Splits on pipes,
    /// bullets, spaced dashes, " at ", runs of spaces, and commas.
    static func splitHeader(_ s: String, commas: Bool = true) -> [String] {
        var parts = [s]
        for sep in [" | ", "|", " • ", " · ", " — ", " – ", " - ", "    ", " at ", " @ "] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        let strong = parts.map { cleanSeparators($0) }.filter { !$0.isEmpty }
        // With pipes or dashes present, commas are part of the pieces ("Item Writer, ELA").
        if strong.count >= 2 || !commas { return strong }
        var out: [String] = []
        for t in strong {
            // Commas: split "Title, Company" but not "Inc." style suffixes.
            let commaParts = t.components(separatedBy: ", ")
            if commaParts.count >= 2 && !commaParts.dropFirst().allSatisfy({ ["inc", "inc.", "llc", "ltd", "ltd."].contains($0.lowercased()) }) {
                out.append(contentsOf: commaParts.map { $0.trimmed }.filter { !$0.isEmpty })
            } else {
                out.append(t)
            }
        }
        return out
    }

    static let titleCues = ["specialist", "developer", "manager", "writer", "editor", "teacher", "director", "coordinator",
                            "analyst", "consultant", "lead", "assistant", "associate", "engineer", "designer", "intern",
                            "instructor", "tutor", "officer", "administrator", "supervisor", "reviewer", "author",
                            "head of", "chair", "president", "founder", "owner", "contractor", "freelance", "fellow",
                            "researcher", "scientist", "professor", "lecturer", "advisor", "adviser", "strategist",
                            "producer", "representative", "technician", "trainer", "facilitator", "principal"]
    static let orgCues = ["inc", "llc", "ltd", "corp", "corporation", "company", "co.", "university", "college", "school",
                          "academy", "institute", "center", "centre", "district", "department", "foundation",
                          "association", "group", "partners", "publishing", "press", "learning", "education", "systems",
                          "labs", "agency", "board", "services", "solutions", "technologies"]
    static let degreeCues = ["bachelor", "master", "b.a", "b.s", "m.a", "m.s", "m.ed", "ph.d", "phd", "ed.d", "mba",
                             "associate of", "associate's", "diploma", "certificate", "degree", "minor", "major", "ba ", "bs ",
                             "ma ", "ms ", "ba,", "bs,", "ba in", "bs in"]

    static func looksLikeTitle(_ s: String, kind: SectionKind) -> Bool {
        let l = " " + s.lowercased() + " "
        if kind == .education { return degreeCues.contains { l.contains($0) } || l.hasPrefix(" ba") || l.hasPrefix(" bs") }
        return titleCues.contains { l.contains(" " + $0) }
    }

    static func looksLikeOrganization(_ s: String) -> Bool {
        let l = " " + s.lowercased() + " "
        return orgCues.contains { l.contains(" " + $0) || l.contains($0 + " ") && $0.count > 4 }
    }
}

extension String {
    /// "present" → "Present"
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}
