import AppKit
import JobBotCore

/// Paginated, text-based PDFs (selectable and searchable, so applicant tracking systems can read
/// them). Uses TextKit for layout and draws the same blocks as the Word writer.
public enum PDFRenderer {
    public static let pageSize = CGSize(width: 612, height: 792) // US Letter

    public static func render(_ blocks: [DocBlock], template: TemplateID, title: String, author: String) -> Data {
        let style = TemplateStyle.style(for: template)
        let text = AttributedBuilder(style: style).build(blocks)
        return draw(text, style: style, title: title, author: author)
    }

    public static func resume(_ profile: Profile, template: TemplateID) -> Data {
        render(Composer.resume(profile), template: template, title: "\(profile.contact.name) Resume".trimmed, author: profile.contact.name)
    }

    public static func coverLetter(_ letter: CoverLetter, profile: Profile, date: Date = Date()) -> Data {
        render(Composer.coverLetter(letter, profile: profile, date: date), template: letter.template,
               title: "\(profile.contact.name) Cover Letter".trimmed, author: profile.contact.name)
    }

    static func draw(_ text: NSAttributedString, style: TemplateStyle, title: String, author: String) -> Data {
        let margin = CGFloat(style.margin)
        let textSize = CGSize(width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin)

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        layout.usesFontLeading = true
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []

        func relayout() {
            while !layout.textContainers.isEmpty { layout.removeTextContainer(at: 0) }
            containers = []
            repeat {
                let container = NSTextContainer(size: textSize)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                containers.append(container)
                let range = layout.glyphRange(for: container)
                if NSMaxRange(range) >= layout.numberOfGlyphs || range.length == 0 { break }
            } while containers.count < 30
        }
        relayout()

        // Keep headings and role lines with what follows: when one ends a page, start it on the
        // next page instead (a form feed moves layout to the next page).
        for _ in 0..<10 {
            var moved = false
            let string = storage.string as NSString
            for container in containers.dropLast() {
                let g = layout.glyphRange(for: container)
                guard g.length > 0 else { continue }
                let charIndex = layout.characterIndexForGlyph(at: NSMaxRange(g) - 1)
                let para = string.paragraphRange(for: NSRange(location: min(charIndex, max(0, string.length - 1)), length: 0))
                guard para.location > 0, para.location < string.length,
                      storage.attribute(.jobBotKeep, at: para.location, effectiveRange: nil) != nil,
                      string.character(at: para.location) != 0x0C else { continue }
                let attrs = storage.attributes(at: para.location, effectiveRange: nil)
                storage.insert(NSAttributedString(string: "\u{0C}", attributes: attrs), at: para.location)
                moved = true
                break
            }
            if !moved { break }
            relayout()
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextAuthor: author, kCGPDFContextCreator: "Job Bot"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return Data() }

        let origin = CGPoint(x: margin, y: margin)
        for container in containers {
            let glyphs = layout.glyphRange(for: container)
            if glyphs.length == 0 && containers.count > 1 { continue }
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = gc
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            layout.drawBackground(forGlyphRange: glyphs, at: origin)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            drawRules(layout: layout, container: container, glyphs: glyphs, storage: storage, origin: origin, width: textSize.width, ctx: ctx)
            ctx.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Thin rules under section headings.
    static func drawRules(layout: NSLayoutManager, container: NSTextContainer, glyphs: NSRange, storage: NSTextStorage,
                          origin: CGPoint, width: CGFloat, ctx: CGContext) {
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.jobBotRule, in: chars, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let g = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: g, in: container)
            let y = origin.y + rect.maxY + 2.5
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(0.7)
            ctx.move(to: CGPoint(x: origin.x, y: y))
            ctx.addLine(to: CGPoint(x: origin.x + width, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}

extension NSAttributedString.Key {
    /// Marks a heading that gets a rule drawn under it (value: NSColor).
    static let jobBotRule = NSAttributedString.Key("JobBotRule")
    /// Marks a paragraph that shouldn't be the last thing on a page.
    static let jobBotKeep = NSAttributedString.Key("JobBotKeep")
}

extension NSFont {
    func sized(_ size: CGFloat) -> NSFont { NSFont(descriptor: fontDescriptor, size: size) ?? self }
}

/// Fonts for each template, with safe fallbacks.
struct TemplateFonts {
    var body: NSFont
    var bold: NSFont
    var italic: NSFont
    var heading: NSFont
    var name: NSFont
    var small: NSFont

    init(style: TemplateStyle) {
        let size = CGFloat(style.bodySize)
        func font(_ names: [String], _ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            for n in names { if let f = NSFont(name: n, size: size) { return f } }
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        switch style.id {
        case .atsSimple:
            body = font(["Helvetica", "ArialMT"], size)
            bold = font(["Helvetica-Bold", "Arial-BoldMT"], size, weight: .bold)
            italic = font(["Helvetica-Oblique", "Arial-ItalicMT"], size)
            heading = font(["Helvetica-Bold", "Arial-BoldMT"], CGFloat(style.headingSize), weight: .bold)
            name = font(["Helvetica-Bold", "Arial-BoldMT"], CGFloat(style.nameSize), weight: .bold)
            small = font(["Helvetica", "ArialMT"], CGFloat(style.smallSize))
        case .modern:
            body = font(["AvenirNext-Regular", "HelveticaNeue"], size)
            bold = font(["AvenirNext-DemiBold", "HelveticaNeue-Bold"], size, weight: .semibold)
            italic = font(["AvenirNext-Italic", "HelveticaNeue-Italic"], size)
            heading = font(["AvenirNext-DemiBold", "HelveticaNeue-Bold"], CGFloat(style.headingSize), weight: .semibold)
            name = font(["AvenirNext-DemiBold", "HelveticaNeue-Bold"], CGFloat(style.nameSize), weight: .semibold)
            small = font(["AvenirNext-Regular", "HelveticaNeue"], CGFloat(style.smallSize))
        case .classic:
            body = font(["Georgia", "TimesNewRomanPSMT"], size)
            bold = font(["Georgia-Bold", "TimesNewRomanPS-BoldMT"], size, weight: .bold)
            italic = font(["Georgia-Italic", "TimesNewRomanPS-ItalicMT"], size)
            heading = font(["Georgia-Bold", "TimesNewRomanPS-BoldMT"], CGFloat(style.headingSize), weight: .bold)
            name = font(["Georgia", "TimesNewRomanPSMT"], CGFloat(style.nameSize))
            small = font(["Georgia", "TimesNewRomanPSMT"], CGFloat(style.smallSize))
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Turns blocks into one attributed string with the template's typography.
struct AttributedBuilder {
    let style: TemplateStyle
    let fonts: TemplateFonts
    let text: NSColor
    let muted: NSColor
    let accent: NSColor
    let width: CGFloat

    init(style: TemplateStyle) {
        self.style = style
        fonts = TemplateFonts(style: style)
        text = NSColor(hex: style.text)
        muted = NSColor(hex: style.muted)
        accent = NSColor(hex: style.accent)
        width = PDFRenderer.pageSize.width - 2 * CGFloat(style.margin)
    }

    func paragraph(before: CGFloat = 0, after: CGFloat = 0, align: NSTextAlignment = .left, indent: CGFloat = 0,
                   tabs: [NSTextTab] = [], lineHeight: CGFloat? = nil, keepWithNext: Bool = false) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.alignment = align
        p.headIndent = indent
        p.firstLineHeadIndent = 0
        p.tabStops = tabs
        p.defaultTabInterval = 36
        p.lineHeightMultiple = lineHeight ?? CGFloat(style.lineHeight)
        p.lineBreakMode = .byWordWrapping
        p.hyphenationFactor = 0
        return p
    }

    func build(_ blocks: [DocBlock]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let center: NSTextAlignment = style.centeredHeader ? .center : .left
        var previous: DocBlock?
        func append(_ s: String, _ attrs: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: s, attributes: attrs))
        }
        for block in blocks {
            if out.length > 0 { append("\n", [.font: fonts.body]) }
            switch block {
            case .name(let s):
                append(s, [.font: fonts.name, .foregroundColor: style.id == .modern ? accent : text,
                           .paragraphStyle: paragraph(after: 2, align: center, lineHeight: 1.0), .kern: style.id == .classic ? 1.0 : 0.0])
            case .headline(let s):
                append(s, [.font: fonts.body.sized(CGFloat(style.bodySize + 1)), .foregroundColor: accent,
                           .paragraphStyle: paragraph(after: 2, align: center)])
            case .contact(let parts):
                append(parts.joined(separator: "  |  "), [.font: fonts.small, .foregroundColor: muted,
                                                          .paragraphStyle: paragraph(after: 4, align: center)])
            case .heading(let s):
                let shown = style.headingUppercase ? s.uppercased() : s
                var attrs: [NSAttributedString.Key: Any] = [.font: fonts.heading, .foregroundColor: accent,
                                                            .paragraphStyle: paragraph(before: CGFloat(style.sectionGap), after: 6, keepWithNext: true),
                                                            .kern: style.headingUppercase ? 0.8 : 0.0]
                attrs[.jobBotKeep] = true
                if style.headingRule { attrs[.jobBotRule] = style.id == .atsSimple ? NSColor(hex: "888888") : accent }
                append(shown, attrs)
            case .entry(let title, let org, let location, let dates):
                // Two left-aligned lines (role, then dates and place). Right-aligned dates look
                // tidy but text extraction (and so some applicant tracking systems) reads them
                // out of order.
                let before: CGFloat
                if case .some(.heading) = previous { before = 0 } else { before = 7 }
                let detail = [dates, location].filter { !$0.isEmpty }.joined(separator: "  ·  ")
                let p1 = paragraph(before: before, after: detail.isEmpty ? 2 : 0)
                let keep1: [NSAttributedString.Key: Any] = [.paragraphStyle: p1, .jobBotKeep: true]
                if !title.isEmpty { append(title, keep1.merging([.font: fonts.bold, .foregroundColor: text]) { a, _ in a }) }
                if !org.isEmpty { append(title.isEmpty ? org : ", \(org)", keep1.merging([.font: fonts.body, .foregroundColor: text]) { a, _ in a }) }
                if !detail.isEmpty {
                    let p2 = paragraph(after: 2.5, lineHeight: 1.1)
                    append("\n", [.font: fonts.small, .paragraphStyle: p1])
                    append(detail, [.font: fonts.small, .foregroundColor: muted, .paragraphStyle: p2, .jobBotKeep: true])
                }
            case .paragraph(let s):
                append(s, [.font: fonts.body, .foregroundColor: text, .paragraphStyle: paragraph(after: 3)])
            case .bullet(let s):
                let p = paragraph(after: 2, indent: 12, tabs: [NSTextTab(textAlignment: .left, location: 12)])
                append("•\t", [.font: fonts.body, .foregroundColor: style.id == .modern ? accent : text, .paragraphStyle: p])
                append(s, [.font: fonts.body, .foregroundColor: text, .paragraphStyle: p])
            case .skills(let items):
                append(items.joined(separator: ", "), [.font: fonts.body, .foregroundColor: text, .paragraphStyle: paragraph(after: 3)])
            case .date(let s):
                append(s, [.font: fonts.body, .foregroundColor: text, .paragraphStyle: paragraph(before: 18, after: 14)])
            case .lines(let ls):
                for (i, l) in ls.enumerated() {
                    if i > 0 { append("\n", [.font: fonts.body]) }
                    append(l, [.font: fonts.body, .foregroundColor: text, .paragraphStyle: paragraph(after: i == ls.count - 1 ? 14 : 0)])
                }
            case .letterParagraph(let s):
                append(s, [.font: fonts.body.sized(CGFloat(style.bodySize + 0.5)), .foregroundColor: text,
                           .paragraphStyle: paragraph(after: 10, lineHeight: CGFloat(style.lineHeight) + 0.05)])
            case .signature(let ls):
                for (i, l) in ls.enumerated() {
                    if i > 0 { append("\n", [.font: fonts.body]) }
                    append(l, [.font: fonts.body.sized(CGFloat(style.bodySize + 0.5)), .foregroundColor: text,
                               .paragraphStyle: paragraph(before: i == 1 ? 28 : 4)])
                }
            }
            previous = block
        }
        return out
    }
}
