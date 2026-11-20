import Foundation

public enum TemplateID: String, Codable, CaseIterable, Identifiable {
    /// Plain, single column, no color: the safest choice for applicant tracking systems.
    case atsSimple
    /// Single column with an accent color and rules under headings.
    case modern
    /// Serif type, centered header, thin rules.
    case classic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .atsSimple: return "ATS Simple"
        case .modern: return "Modern"
        case .classic: return "Classic"
        }
    }

    public var blurb: String {
        switch self {
        case .atsSimple: return "Plain single column with standard headings. Best for online application systems."
        case .modern: return "Single column with an accent color. Still reads cleanly as plain text."
        case .classic: return "Serif type and a centered header for a traditional look."
        }
    }
}

/// A resume made for one job. Starts as a copy of the master profile; the master never changes
/// when this does.
public struct TailoredResume: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var jobID: UUID?
    public var name: String
    public var content: Profile
    public var template: TemplateID
    public var suggestions: [Suggestion]
    public var created: Date
    public var updated: Date

    public init(id: UUID = UUID(), jobID: UUID?, name: String, content: Profile, template: TemplateID = .atsSimple,
                suggestions: [Suggestion] = [], created: Date = Date()) {
        self.id = id
        self.jobID = jobID
        self.name = name
        self.content = content
        self.template = template
        self.suggestions = suggestions
        self.created = created
        self.updated = created
    }
}

public struct CoverLetter: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var jobID: UUID?
    public var name: String
    /// "Dear Hiring Team,"
    public var greeting: String
    /// Body paragraphs separated by blank lines.
    public var body: String
    /// "Sincerely,"
    public var closing: String
    public var signature: String
    /// Optional recipient block (company, address), one item per line.
    public var recipient: String
    public var template: TemplateID
    /// Notes from drafting: gaps not mentioned, sentences to check.
    public var reviewNotes: [String]
    public var created: Date
    public var updated: Date

    public init(id: UUID = UUID(), jobID: UUID?, name: String, greeting: String = "Dear Hiring Team,", body: String = "",
                closing: String = "Sincerely,", signature: String = "", recipient: String = "",
                template: TemplateID = .atsSimple, reviewNotes: [String] = [], created: Date = Date()) {
        self.id = id
        self.jobID = jobID
        self.name = name
        self.greeting = greeting
        self.body = body
        self.closing = closing
        self.signature = signature
        self.recipient = recipient
        self.template = template
        self.reviewNotes = reviewNotes
        self.created = created
        self.updated = created
    }

    public var paragraphs: [String] {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
    }

    public var plainText: String {
        var parts: [String] = []
        if !recipient.trimmed.isEmpty { parts.append(recipient.trimmed) }
        if !greeting.trimmed.isEmpty { parts.append(greeting.trimmed) }
        parts.append(contentsOf: paragraphs)
        let sign = [closing.trimmed, signature.trimmed].filter { !$0.isEmpty }.joined(separator: "\n")
        if !sign.isEmpty { parts.append(sign) }
        return parts.joined(separator: "\n\n")
    }
}

/// A saved copy of a document, for comparing and restoring.
public struct VersionSnapshot: Codable, Equatable, Hashable, Identifiable {
    public enum Owner: Codable, Equatable, Hashable {
        case master
        case resume(UUID)
        case coverLetter(UUID)
    }

    public var id: UUID
    public var owner: Owner
    public var date: Date
    public var label: String
    public var profile: Profile?
    public var letter: CoverLetter?

    public init(id: UUID = UUID(), owner: Owner, date: Date = Date(), label: String, profile: Profile? = nil, letter: CoverLetter? = nil) {
        self.id = id
        self.owner = owner
        self.date = date
        self.label = label
        self.profile = profile
        self.letter = letter
    }

    public var plainText: String {
        if let profile { return PlainTextRenderer.resume(profile) }
        if let letter { return letter.plainText }
        return ""
    }
}

// MARK: - Suggestions

public enum SuggestionKind: String, Codable {
    /// Put the most relevant bullets of a role first.
    case reorderBullets
    /// Put matching skills first in the skills list.
    case reorderSkills
    /// Add a skill to the skills list that the profile already shows elsewhere.
    case addSkill
    /// Use the posting's wording for something the profile already says another way.
    case alignTerm
    /// Rewrite the summary (only from facts in the profile).
    case rewriteSummary
    /// Rewrite one bullet (only from facts in the profile).
    case rewriteBullet
    /// Leave a less relevant bullet out of this version (it stays in the master).
    case hideBullet
}

public struct Suggestion: Codable, Equatable, Hashable, Identifiable {
    public enum Status: String, Codable {
        case pending, accepted, rejected
    }

    public var id: UUID
    public var kind: SuggestionKind
    public var title: String
    /// Why it may help, in plain words.
    public var explanation: String
    public var before: String
    /// The proposed text; the person can edit it before accepting.
    public var after: String
    public var target: EvidenceRef
    /// Lines of the job description that motivate the change.
    public var jobEvidence: [String]
    /// Profile details that support the change.
    public var profileEvidence: [ProfileUnit]
    /// Things to check before using it (facts not found in the profile, for example).
    public var warnings: [String]
    public var status: Status
    /// "Job Bot" for built-in rules, or the AI service that drafted it.
    public var origin: String
    /// For reorders: the new order of IDs (bullets) or items (skills).
    public var newOrder: [String]

    public init(id: UUID = UUID(), kind: SuggestionKind, title: String, explanation: String, before: String, after: String,
                target: EvidenceRef, jobEvidence: [String] = [], profileEvidence: [ProfileUnit] = [], warnings: [String] = [],
                status: Status = .pending, origin: String = "Job Bot", newOrder: [String] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.explanation = explanation
        self.before = before
        self.after = after
        self.target = target
        self.jobEvidence = jobEvidence
        self.profileEvidence = profileEvidence
        self.warnings = warnings
        self.status = status
        self.origin = origin
        self.newOrder = newOrder
    }
}

extension ProfileUnit: Codable {
    enum CodingKeys: String, CodingKey { case ref, text, location, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(EvidenceRef.self, forKey: .ref)
        text = try c.decode(String.self, forKey: .text)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ref, forKey: .ref)
        try c.encode(text, forKey: .text)
        try c.encode(location, forKey: .location)
        try c.encode(label, forKey: .label)
    }
}
