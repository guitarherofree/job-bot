import Foundation

/// Visual settings shared by the PDF and Word output, so both look alike.
public struct TemplateStyle: Equatable {
    public var id: TemplateID
    /// Word font names (fonts every copy of Word has).
    public var docxBodyFont: String
    public var docxHeadingFont: String
    public var bodySize: Double
    public var smallSize: Double
    public var nameSize: Double
    public var headingSize: Double
    /// Hex colors without "#".
    public var accent: String
    public var text: String
    public var muted: String
    public var headingUppercase: Bool
    public var headingRule: Bool
    public var centeredHeader: Bool
    /// Page margins in points.
    public var margin: Double
    /// Line height as a multiple of the font size.
    public var lineHeight: Double
    /// Space before a section heading, in points.
    public var sectionGap: Double

    public static func style(for id: TemplateID) -> TemplateStyle {
        switch id {
        case .atsSimple:
            return TemplateStyle(id: id, docxBodyFont: "Arial", docxHeadingFont: "Arial", bodySize: 10.5, smallSize: 9.5,
                                 nameSize: 18, headingSize: 11, accent: "000000", text: "111111", muted: "444444",
                                 headingUppercase: true, headingRule: true, centeredHeader: false, margin: 54,
                                 lineHeight: 1.18, sectionGap: 12)
        case .modern:
            return TemplateStyle(id: id, docxBodyFont: "Calibri", docxHeadingFont: "Calibri", bodySize: 10.5, smallSize: 9.5,
                                 nameSize: 24, headingSize: 11.5, accent: "1F5F7A", text: "1E2329", muted: "5A6470",
                                 headingUppercase: true, headingRule: true, centeredHeader: false, margin: 48,
                                 lineHeight: 1.1, sectionGap: 12)
        case .classic:
            return TemplateStyle(id: id, docxBodyFont: "Georgia", docxHeadingFont: "Georgia", bodySize: 10.5, smallSize: 9.5,
                                 nameSize: 20, headingSize: 11.5, accent: "3B3B3B", text: "1A1A1A", muted: "555555",
                                 headingUppercase: false, headingRule: true, centeredHeader: true, margin: 58,
                                 lineHeight: 1.2, sectionGap: 13)
        }
    }
}

/// The layout-independent content of a document. Both the PDF and the Word writer draw these.
public enum DocBlock: Equatable {
    case name(String)
    case headline(String)
    case contact([String])
    case heading(String)
    /// Role or degree line: title and organization on the left, dates on the right.
    case entry(title: String, organization: String, location: String, dates: String)
    case paragraph(String)
    case bullet(String)
    case skills([String])
    case date(String)
    case lines([String])
    case letterParagraph(String)
    case signature([String])
}

public enum Composer {
    public static func resume(_ profile: Profile) -> [DocBlock] {
        let p = profile.visible
        var blocks = header(p)
        if !p.summary.trimmed.isEmpty {
            blocks.append(.heading("Summary"))
            blocks.append(.paragraph(p.summary.trimmed))
        }
        for s in p.sections where !s.isEmpty {
            blocks.append(.heading(s.title.trimmed.isEmpty ? s.kind.defaultTitle : s.title.trimmed))
            if s.kind.usesList {
                let items = s.items.map { $0.trimmed }.filter { !$0.isEmpty }
                if !items.isEmpty { blocks.append(.skills(items)) }
            }
            for e in s.entries {
                let title = e.title.trimmed, org = e.organization.trimmed
                if !title.isEmpty || !org.isEmpty || !e.dateRange.isEmpty {
                    blocks.append(.entry(title: title, organization: org, location: e.location.trimmed, dates: e.dateRange))
                }
                if !e.details.trimmed.isEmpty { blocks.append(.paragraph(e.details.trimmed)) }
                for b in e.bullets where !b.text.trimmed.isEmpty {
                    blocks.append(.bullet(b.text.trimmed))
                }
            }
        }
        return blocks
    }

    public static func coverLetter(_ letter: CoverLetter, profile: Profile, date: Date = Date()) -> [DocBlock] {
        var blocks = header(profile)
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_US")
        blocks.append(.date(f.string(from: date)))
        let recipient = letter.recipient.components(separatedBy: "\n").map { $0.trimmed }.filter { !$0.isEmpty }
        if !recipient.isEmpty { blocks.append(.lines(recipient)) }
        if !letter.greeting.trimmed.isEmpty { blocks.append(.letterParagraph(letter.greeting.trimmed)) }
        for p in letter.paragraphs { blocks.append(.letterParagraph(p)) }
        let sign = [letter.closing.trimmed, letter.signature.trimmed.isEmpty ? profile.contact.name.trimmed : letter.signature.trimmed]
            .filter { !$0.isEmpty }
        if !sign.isEmpty { blocks.append(.signature(sign)) }
        return blocks
    }

    static func header(_ p: Profile) -> [DocBlock] {
        var blocks: [DocBlock] = []
        if !p.contact.name.trimmed.isEmpty { blocks.append(.name(p.contact.name.trimmed)) }
        if !p.headline.trimmed.isEmpty { blocks.append(.headline(p.headline.trimmed)) }
        let parts = p.contact.lineParts
        if !parts.isEmpty { blocks.append(.contact(parts)) }
        return blocks
    }
}

/// Plain text versions: what an applicant tracking system will read, and what gets copied.
public enum PlainTextRenderer {
    public static func render(_ blocks: [DocBlock]) -> String {
        var out: [String] = []
        var lastWasHeading = false
        for b in blocks {
            switch b {
            case .name(let s): out.append(s)
            case .headline(let s): out.append(s)
            case .contact(let parts): out.append(parts.joined(separator: " | "))
            case .heading(let s):
                out.append("")
                out.append(s.uppercased())
                lastWasHeading = true
                continue
            case .entry(let title, let org, let location, let dates):
                if !lastWasHeading { out.append("") }
                var line = [title, org].filter { !$0.isEmpty }.joined(separator: ", ")
                if !location.isEmpty { line += line.isEmpty ? location : ", \(location)" }
                if !dates.isEmpty { line += line.isEmpty ? dates : " (\(dates))" }
                out.append(line)
            case .paragraph(let s): out.append(s)
            case .bullet(let s): out.append("- \(s)")
            case .skills(let items): out.append(items.joined(separator: ", "))
            case .date(let s):
                out.append("")
                out.append(s)
            case .lines(let ls):
                out.append("")
                out.append(contentsOf: ls)
            case .letterParagraph(let s):
                out.append("")
                out.append(s)
            case .signature(let ls):
                out.append("")
                out.append(contentsOf: ls)
            }
            lastWasHeading = false
        }
        return out.joined(separator: "\n").trimmed + "\n"
    }

    public static func resume(_ profile: Profile) -> String { render(Composer.resume(profile)) }

    public static func coverLetter(_ letter: CoverLetter, profile: Profile, date: Date = Date()) -> String {
        render(Composer.coverLetter(letter, profile: profile, date: date))
    }
}
