import Foundation

/// Writes Word (.docx) files from document blocks. Uses real Word styles (Title, Heading 1,
/// List Bullet) and real bullets, so the file stays easy for applicant tracking systems to read.
public enum DocxWriter {
    public static func document(_ blocks: [DocBlock], style: TemplateStyle, title: String, author: String,
                                date: Date = Date()) -> Data {
        let body = blocks.map { paragraph(for: $0, style: style) }.joined()
        let pageWidth = 12240, pageHeight = 15840
        let margin = twips(style.margin)
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>\(body)<w:sectPr><w:pgSz w:w="\(pageWidth)" w:h="\(pageHeight)"/><w:pgMar w:top="\(margin)" w:right="\(margin)" w:bottom="\(margin)" w:left="\(margin)" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        let entries: [Zip.Entry] = [
            Zip.Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            Zip.Entry(name: "_rels/.rels", data: Data(rootRels.utf8)),
            Zip.Entry(name: "docProps/core.xml", data: Data(core(title: title, author: author, date: date).utf8)),
            Zip.Entry(name: "docProps/app.xml", data: Data(app.utf8)),
            Zip.Entry(name: "word/_rels/document.xml.rels", data: Data(documentRels.utf8)),
            Zip.Entry(name: "word/document.xml", data: Data(document.utf8)),
            Zip.Entry(name: "word/styles.xml", data: Data(styles(style).utf8)),
            Zip.Entry(name: "word/numbering.xml", data: Data(numbering.utf8)),
            Zip.Entry(name: "word/settings.xml", data: Data(settings.utf8)),
        ]
        return Zip.archive(entries, date: date)
    }

    // MARK: Paragraphs

    static func paragraph(for block: DocBlock, style: TemplateStyle) -> String {
        let center = style.centeredHeader ? "<w:jc w:val=\"center\"/>" : ""
        switch block {
        case .name(let s):
            return p(props: "<w:pStyle w:val=\"Title\"/>\(center)", runs: run(s))
        case .headline(let s):
            return p(props: "\(center)<w:spacing w:before=\"0\" w:after=\"40\"/>", runs: run(s, color: style.accent, size: style.bodySize + 1))
        case .contact(let parts):
            let joined = parts.joined(separator: "  |  ")
            return p(props: "\(center)<w:spacing w:before=\"0\" w:after=\"120\"/>", runs: run(joined, color: style.muted, size: style.smallSize))
        case .heading(let s):
            return p(props: "<w:pStyle w:val=\"Heading1\"/>", runs: run(s))
        case .entry(let title, let org, let location, let dates):
            var runs = ""
            if !title.isEmpty { runs += run(title, bold: true) }
            if !org.isEmpty { runs += run(title.isEmpty ? org : ", \(org)") }
            let detail = [dates, location].filter { !$0.isEmpty }.joined(separator: "  ·  ")
            var out = p(props: "<w:keepNext/><w:spacing w:before=\"120\" w:after=\"\(detail.isEmpty ? 40 : 0)\"/>", runs: runs)
            if !detail.isEmpty {
                out += p(props: "<w:keepNext/><w:spacing w:before=\"0\" w:after=\"40\"/>", runs: run(detail, color: style.muted, size: style.smallSize))
            }
            return out
        case .paragraph(let s):
            return p(props: "<w:spacing w:before=\"0\" w:after=\"60\"/>", runs: run(s))
        case .bullet(let s):
            return p(props: "<w:pStyle w:val=\"ListBullet\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>", runs: run(s))
        case .skills(let items):
            return p(props: "<w:spacing w:before=\"0\" w:after=\"60\"/>", runs: run(items.joined(separator: ", ")))
        case .date(let s):
            return p(props: "<w:spacing w:before=\"240\" w:after=\"240\"/>", runs: run(s))
        case .lines(let ls):
            return ls.enumerated().map { i, l in
                p(props: "<w:spacing w:before=\"0\" w:after=\"\(i == ls.count - 1 ? 240 : 0)\"/>", runs: run(l))
            }.joined()
        case .letterParagraph(let s):
            return p(props: "<w:spacing w:before=\"0\" w:after=\"200\"/>", runs: run(s))
        case .signature(let ls):
            return ls.enumerated().map { i, l in
                p(props: "<w:spacing w:before=\"\(i == 1 ? 480 : 0)\" w:after=\"0\"/>", runs: run(l))
            }.joined()
        }
    }

    static func p(props: String, runs: String) -> String {
        "<w:p><w:pPr>\(props)</w:pPr>\(runs)</w:p>"
    }

    static func run(_ text: String, bold: Bool = false, italic: Bool = false, color: String? = nil, size: Double? = nil) -> String {
        var rPr = ""
        if bold { rPr += "<w:b/>" }
        if italic { rPr += "<w:i/>" }
        if let color { rPr += "<w:color w:val=\"\(color)\"/>" }
        if let size { rPr += "<w:sz w:val=\"\(halfPoints(size))\"/><w:szCs w:val=\"\(halfPoints(size))\"/>" }
        let props = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
        // Word wants line breaks as <w:br/>.
        let pieces = text.components(separatedBy: "\n").map { "<w:t xml:space=\"preserve\">\(escape($0))</w:t>" }
        return "<w:r>\(props)\(pieces.joined(separator: "<w:br/>"))</w:r>"
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // XML 1.0 forbids most control characters.
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func twips(_ points: Double) -> Int { Int((points * 20).rounded()) }
    static func halfPoints(_ points: Double) -> Int { Int((points * 2).rounded()) }

    // MARK: Package parts

    static func styles(_ s: TemplateStyle) -> String {
        let bodySize = halfPoints(s.bodySize)
        let line = Int((240 * s.lineHeight).rounded())
        let rule = s.headingRule
            ? "<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"\(s.accent)\"/></w:pBdr>"
            : ""
        let caps = s.headingUppercase ? "<w:caps/>" : ""
        let center = s.centeredHeader ? "<w:jc w:val=\"center\"/>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(s.docxBodyFont)" w:hAnsi="\(s.docxBodyFont)" w:eastAsia="\(s.docxBodyFont)" w:cs="\(s.docxBodyFont)"/><w:color w:val="\(s.text)"/><w:sz w:val="\(bodySize)"/><w:szCs w:val="\(bodySize)"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="\(line)" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr>\(center)<w:spacing w:before="0" w:after="40"/></w:pPr><w:rPr><w:rFonts w:ascii="\(s.docxHeadingFont)" w:hAnsi="\(s.docxHeadingFont)" w:cs="\(s.docxHeadingFont)"/><w:b/><w:color w:val="\(s.id == .modern ? s.accent : s.text)"/><w:sz w:val="\(halfPoints(s.nameSize))"/><w:szCs w:val="\(halfPoints(s.nameSize))"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/>\(rule)<w:spacing w:before="\(twips(s.sectionGap))" w:after="60"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:rFonts w:ascii="\(s.docxHeadingFont)" w:hAnsi="\(s.docxHeadingFont)" w:cs="\(s.docxHeadingFont)"/><w:b/>\(caps)<w:color w:val="\(s.accent)"/><w:spacing w:val="\(s.headingUppercase ? 10 : 0)"/><w:sz w:val="\(halfPoints(s.headingSize))"/><w:szCs w:val="\(halfPoints(s.headingSize))"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr><w:spacing w:before="0" w:after="30"/><w:ind w:left="360" w:hanging="240"/></w:pPr></w:style>\
        </w:styles>
        """
    }

    static let numbering = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="360" w:hanging="240"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/></w:rPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
    """

    static let settings = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:defaultTabStop w:val="720"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
    """

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
    """

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
    """

    static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>
    """

    static let app = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Job Bot</Application></Properties>
    """

    static func core(title: String, author: String, date: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(escape(title))</dc:title><dc:creator>\(escape(author))</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(iso)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(iso)</dcterms:modified></cp:coreProperties>
        """
    }
}
