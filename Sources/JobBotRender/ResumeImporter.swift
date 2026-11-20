import AppKit
import PDFKit
import JobBotCore

/// Reads the text out of a resume file: PDF, Word (.docx), plain text, or RTF.
public enum ResumeImporter {
    public enum ImportError: Error, LocalizedError {
        case unreadable(String)
        case noText(String)
        case unsupported(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "Job Bot couldn't open the file. \(why)"
            case .noText(let why): return why
            case .unsupported(let ext): return "Job Bot can't read .\(ext) files. Save the resume as PDF, Word (.docx) or plain text, or paste its text instead."
            }
        }
    }

    public static let supportedExtensions = ["pdf", "docx", "txt", "text", "md", "rtf", "doc"]

    public static func text(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: url) else {
                throw ImportError.unreadable("It may be damaged or password protected.")
            }
            if doc.isLocked { throw ImportError.unreadable("The PDF is password protected. Unlock it and try again.") }
            var pages: [String] = []
            for i in 0..<doc.pageCount {
                if let s = doc.page(at: i)?.string { pages.append(s) }
            }
            let text = pages.joined(separator: "\n")
            if text.trimmed.count < 40 {
                throw ImportError.noText("This PDF doesn't contain selectable text (it may be a scanned image). Open it, copy the text, and use “Paste Resume Text” instead, or import the Word version.")
            }
            return text
        case "docx":
            do {
                let data = try Data(contentsOf: url)
                let text = try DocxReader.text(fromDocx: data)
                if text.trimmed.isEmpty { throw ImportError.noText("The Word document appears to be empty.") }
                return text
            } catch let e as ImportError {
                throw e
            } catch {
                // Fall back to the system's Word reader.
                if let s = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                                   documentAttributes: nil).string, !s.trimmed.isEmpty {
                    return s
                }
                throw ImportError.unreadable(error.localizedDescription)
            }
        case "txt", "text", "md":
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
            if let s = try? String(contentsOf: url, encoding: .utf16) { return s }
            if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
            throw ImportError.unreadable("The text encoding wasn't recognized.")
        case "rtf", "doc":
            let type: NSAttributedString.DocumentType = ext == "rtf" ? .rtf : .docFormat
            do {
                let s = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
                if s.trimmed.isEmpty { throw ImportError.noText("The document appears to be empty.") }
                return s
            } catch let e as ImportError {
                throw e
            } catch {
                throw ImportError.unreadable(error.localizedDescription)
            }
        default:
            throw ImportError.unsupported(ext.isEmpty ? "unknown" : ext)
        }
    }
}

/// Text of a PDF made by Job Bot (used to check exports stay readable as plain text).
public enum PDFText {
    public static func text(of data: Data) -> String {
        guard let doc = PDFDocument(data: data) else { return "" }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }

    public static func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }
}
