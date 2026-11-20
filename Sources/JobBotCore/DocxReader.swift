import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Extracts the text of a .docx file, one paragraph per line; list paragraphs start with "• ".
public enum DocxReader {
    public static func text(fromDocx data: Data) throws -> String {
        guard let xml = try Zip.read("word/document.xml", from: data) else {
            throw Zip.ReadError.unsupported("no word/document.xml")
        }
        return text(fromDocumentXML: xml)
    }

    public static func text(fromDocumentXML xml: Data) -> String {
        let delegate = Collector()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        delegate.endParagraph()
        return delegate.lines.joined(separator: "\n")
    }

    final class Collector: NSObject, XMLParserDelegate {
        var lines: [String] = []
        var paragraph = ""
        var inText = false
        var isList = false
        var inParagraphProperties = false
        var depthInDeleted = 0

        func endParagraph() {
            let t = paragraph.replacingOccurrences(of: "\u{00A0}", with: " ")
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty || !paragraph.isEmpty {
                lines.append(isList && TextTools.bulletText(trimmed) == nil ? "• " + trimmed : t.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            paragraph = ""
            isList = false
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            switch name {
            case "w:p": paragraph = ""; isList = false
            case "w:pPr": inParagraphProperties = true
            case "w:numPr": if inParagraphProperties { isList = true }
            case "w:pStyle":
                if inParagraphProperties, let v = attributes["w:val"]?.lowercased(), v.contains("list") || v.contains("bullet") {
                    isList = true
                }
            case "w:t": if depthInDeleted == 0 { inText = true }
            case "w:tab": if depthInDeleted == 0 && !inParagraphProperties { paragraph += "    " }
            case "w:br", "w:cr": if depthInDeleted == 0 { paragraph += "\n" }
            case "w:del": depthInDeleted += 1
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:p": endParagraph()
            case "w:pPr": inParagraphProperties = false
            case "w:t": inText = false
            case "w:del": depthInDeleted = max(0, depthInDeleted - 1)
            case "w:tc": paragraph += "    "
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { paragraph += string }
        }
    }
}
