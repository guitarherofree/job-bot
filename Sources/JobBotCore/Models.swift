import Foundation

// Data model for the profile (the master resume) and its sections.
//
// Storage note: everything here is saved as JSON. Fields added in later versions must be
// Optional (or have a custom decoder) so files written by older versions still load.

public struct ContactInfo: Codable, Equatable, Hashable {
    public var name: String
    public var email: String
    public var phone: String
    public var location: String
    /// LinkedIn, portfolio and similar links, as the person wrote them.
    public var links: [String]

    public init(name: String = "", email: String = "", phone: String = "", location: String = "", links: [String] = []) {
        self.name = name
        self.email = email
        self.phone = phone
        self.location = location
        self.links = links
    }

    public var isEmpty: Bool {
        name.isEmpty && email.isEmpty && phone.isEmpty && location.isEmpty && links.isEmpty
    }

    /// The pieces shown on the contact line, in order, skipping empty ones.
    public var lineParts: [String] {
        ([location, phone, email] + links).map { $0.trimmed }.filter { !$0.isEmpty }
    }
}

public enum SectionKind: String, Codable, CaseIterable, Identifiable {
    case experience
    case education
    case skills
    case certifications
    case projects
    case awards
    case publications
    case volunteer
    case other

    public var id: String { rawValue }

    public var defaultTitle: String {
        switch self {
        case .experience: return "Experience"
        case .education: return "Education"
        case .skills: return "Skills"
        case .certifications: return "Certifications"
        case .projects: return "Projects"
        case .awards: return "Awards"
        case .publications: return "Publications"
        case .volunteer: return "Volunteer Experience"
        case .other: return "Additional Information"
        }
    }

    /// Skills are a plain list; every other kind holds entries (a role, a degree, a credential).
    public var usesList: Bool { self == .skills }

    /// Labels for the entry fields in the editor.
    public var titleLabel: String {
        switch self {
        case .experience, .volunteer: return "Job title"
        case .education: return "Degree or program"
        case .certifications: return "Credential"
        case .projects: return "Project"
        case .awards: return "Award"
        case .publications: return "Title"
        case .skills, .other: return "Title"
        }
    }

    public var organizationLabel: String {
        switch self {
        case .experience, .volunteer: return "Employer"
        case .education: return "School"
        case .certifications: return "Issuer"
        case .publications: return "Publisher"
        case .projects, .awards, .skills, .other: return "Organization"
        }
    }
}

public struct Bullet: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct ResumeEntry: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var organization: String
    public var location: String
    /// Dates are kept as the person wrote them ("Jan 2019", "2019", "Present").
    public var startDate: String
    public var endDate: String
    public var bullets: [Bullet]
    /// Free text under the entry (for example coursework or a short description).
    public var details: String
    /// Hidden entries stay in the profile but are left out of this document.
    public var hidden: Bool

    public init(id: UUID = UUID(), title: String = "", organization: String = "", location: String = "",
                startDate: String = "", endDate: String = "", bullets: [Bullet] = [], details: String = "",
                hidden: Bool = false) {
        self.id = id
        self.title = title
        self.organization = organization
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.bullets = bullets
        self.details = details
        self.hidden = hidden
    }

    /// "Jan 2019 – Present", "2019", or "".
    public var dateRange: String {
        let s = startDate.trimmed, e = endDate.trimmed
        if s.isEmpty { return e }
        if e.isEmpty { return s }
        return "\(s) – \(e)"
    }

    public var headline: String {
        [title.trimmed, organization.trimmed].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

public struct ResumeSection: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var kind: SectionKind
    public var title: String
    public var entries: [ResumeEntry]
    /// Used by list sections (skills).
    public var items: [String]
    public var hidden: Bool

    public init(id: UUID = UUID(), kind: SectionKind, title: String? = nil, entries: [ResumeEntry] = [],
                items: [String] = [], hidden: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.entries = entries
        self.items = items
        self.hidden = hidden
    }

    public var isEmpty: Bool {
        entries.isEmpty && items.allSatisfy { $0.trimmed.isEmpty }
    }
}

/// The person's experience, as they described it. The master resume is a Profile; each tailored
/// resume holds its own copy.
public struct Profile: Codable, Equatable, Hashable {
    public var contact: ContactInfo
    public var headline: String
    public var summary: String
    public var sections: [ResumeSection]
    /// Facts the person added while answering follow-up questions ("Yes, I used QTI at Pearson").
    /// They count as evidence for matching but are not printed on the resume.
    public var notes: [ProfileNote]

    public init(contact: ContactInfo = ContactInfo(), headline: String = "", summary: String = "",
                sections: [ResumeSection] = [], notes: [ProfileNote] = []) {
        self.contact = contact
        self.headline = headline
        self.summary = summary
        self.sections = sections
        self.notes = notes
    }

    public var isEmpty: Bool {
        contact.isEmpty && headline.trimmed.isEmpty && summary.trimmed.isEmpty && sections.allSatisfy { $0.isEmpty }
    }

    public static let starter = Profile(sections: [
        ResumeSection(kind: .experience),
        ResumeSection(kind: .education),
        ResumeSection(kind: .skills),
    ])

    public func section(_ id: UUID) -> ResumeSection? { sections.first { $0.id == id } }

    public func entry(_ id: UUID) -> (ResumeSection, ResumeEntry)? {
        for s in sections {
            if let e = s.entries.first(where: { $0.id == id }) { return (s, e) }
        }
        return nil
    }
}

public struct ProfileNote: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// The question or topic this answers ("Experience with QTI").
    public var topic: String
    public var text: String
    public var created: Date

    public init(id: UUID = UUID(), topic: String, text: String, created: Date = Date()) {
        self.id = id
        self.topic = topic
        self.text = text
        self.created = created
    }
}

// MARK: - Evidence

/// Points at one piece of the profile.
public struct EvidenceRef: Codable, Equatable, Hashable {
    public enum Field: String, Codable {
        case headline, summary, entryTitle, entryDetails, bullet, skill, note, contact
    }

    public var field: Field
    public var sectionID: UUID?
    public var entryID: UUID?
    public var bulletID: UUID?
    /// Skill text, or the note ID as a string.
    public var key: String?

    public init(field: Field, sectionID: UUID? = nil, entryID: UUID? = nil, bulletID: UUID? = nil, key: String? = nil) {
        self.field = field
        self.sectionID = sectionID
        self.entryID = entryID
        self.bulletID = bulletID
        self.key = key
    }
}

/// One unit of the profile that can support a claim: a bullet, a skill, the summary...
public struct ProfileUnit: Equatable, Hashable {
    public var ref: EvidenceRef
    public var text: String
    /// Where it lives, for people: "Experience › Assessment Specialist, Pearson".
    public var location: String
    /// Short stable label used when talking to an AI service ("B12").
    public var label: String
}

extension Profile {
    /// Every piece of the profile that can serve as evidence, with labels S1, H1, E3, B12, K4, N1.
    public func units(includeHidden: Bool = true) -> [ProfileUnit] {
        var out: [ProfileUnit] = []
        var counters: [String: Int] = [:]
        func next(_ prefix: String) -> String {
            counters[prefix, default: 0] += 1
            return "\(prefix)\(counters[prefix]!)"
        }
        if !headline.trimmed.isEmpty {
            out.append(ProfileUnit(ref: EvidenceRef(field: .headline), text: headline.trimmed, location: "Headline", label: next("H")))
        }
        if !summary.trimmed.isEmpty {
            out.append(ProfileUnit(ref: EvidenceRef(field: .summary), text: summary.trimmed, location: "Summary", label: next("S")))
        }
        for s in sections where includeHidden || !s.hidden {
            if s.kind.usesList {
                for item in s.items where !item.trimmed.isEmpty {
                    out.append(ProfileUnit(ref: EvidenceRef(field: .skill, sectionID: s.id, key: item),
                                           text: item.trimmed, location: s.title, label: next("K")))
                }
            }
            for e in s.entries where includeHidden || !e.hidden {
                let place = e.headline.isEmpty ? s.title : "\(s.title) › \(e.headline)"
                let titleText = [e.title, e.organization, e.dateRange].map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !titleText.isEmpty {
                    out.append(ProfileUnit(ref: EvidenceRef(field: .entryTitle, sectionID: s.id, entryID: e.id),
                                           text: titleText, location: place, label: next("E")))
                }
                if !e.details.trimmed.isEmpty {
                    out.append(ProfileUnit(ref: EvidenceRef(field: .entryDetails, sectionID: s.id, entryID: e.id),
                                           text: e.details.trimmed, location: place, label: next("D")))
                }
                for b in e.bullets where !b.text.trimmed.isEmpty {
                    out.append(ProfileUnit(ref: EvidenceRef(field: .bullet, sectionID: s.id, entryID: e.id, bulletID: b.id),
                                           text: b.text.trimmed, location: place, label: next("B")))
                }
            }
        }
        for n in notes where !n.text.trimmed.isEmpty {
            out.append(ProfileUnit(ref: EvidenceRef(field: .note, key: n.id.uuidString),
                                   text: n.topic.isEmpty ? n.text : "\(n.topic): \(n.text)",
                                   location: "Your notes", label: next("N")))
        }
        return out
    }

    /// All the text of the profile, for checking whether a fact appears anywhere in it.
    public var corpus: String {
        var parts = [contact.name, contact.location, headline, summary]
        for s in sections {
            parts.append(s.title)
            parts.append(contentsOf: s.items)
            for e in s.entries {
                parts.append(contentsOf: [e.title, e.organization, e.location, e.startDate, e.endDate, e.details])
                parts.append(contentsOf: e.bullets.map { $0.text })
            }
        }
        parts.append(contentsOf: notes.map { "\($0.topic) \($0.text)" })
        return parts.joined(separator: "\n")
    }

    /// Profile without hidden sections and entries (what gets printed).
    public var visible: Profile {
        var p = self
        p.sections = sections.filter { !$0.hidden }.map { s in
            var s = s
            s.entries = s.entries.filter { !$0.hidden }
            return s
        }
        return p
    }
}

// MARK: - String helpers

extension StringProtocol {
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Collapses runs of whitespace into single spaces.
    public var squashed: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
