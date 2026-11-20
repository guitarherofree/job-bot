import Foundation

/// Reads job pages: plain text from HTML, plus the structured JobPosting data many career sites
/// publish for search engines (schema.org JSON-LD).
public enum HTMLText {
    public static func text(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "head", "template", "iframe"] {
            s = Rx("<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>").replace(s, with: " ")
        }
        s = Rx("<!--[\\s\\S]*?-->").replace(s, with: " ")
        s = Rx("<br\\s*/?>").replace(s, with: "\n")
        s = Rx("<li\\b[^>]*>").replace(s, with: "\n• ")
        s = Rx("</(p|div|h[1-6]|li|tr|ul|ol|section|article|header|footer|table|dd|dt|blockquote)>").replace(s, with: "\n")
        s = Rx("<(p|div|h[1-6]|tr|ul|ol|section|article|table|dd|dt|blockquote)\\b[^>]*>").replace(s, with: "\n")
        s = Rx("</t[dh]>").replace(s, with: "  ")
        s = Rx("<[^>]+>").replace(s, with: "")
        s = decodeEntities(s)
        var lines: [String] = []
        for raw in s.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\u{00A0}", with: " ").squashed
            if line.isEmpty || line == "•" { continue }
            if lines.last == line { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“", "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "trade": "™", "reg": "®", "copy": "©", "deg": "°", "frac12": "½", "times": "×", "eacute": "é", "egrave": "è",
        "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú", "ntilde": "ñ", "ccedil": "ç", "uuml": "ü", "ouml": "ö",
        "auml": "ä", "shy": "", "zwnj": "", "zwj": "", "ensp": " ", "emsp": " ", "thinsp": " ",
    ]

    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let name = String(s[s.index(after: i)..<semi])
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    if let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                } else if name.hasPrefix("#") {
                    if let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                } else {
                    replacement = named[name.lowercased()]
                }
                if let r = replacement {
                    out += r
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    public static func title(fromHTML html: String) -> String? {
        if let m = Rx("<meta[^>]+property=[\"']og:title[\"'][^>]*content=[\"']([^\"']*)[\"']").firstMatch(html), !m[1].isEmpty {
            return decodeEntities(m[1]).squashed
        }
        if let m = Rx("<title[^>]*>([\\s\\S]*?)</title>").firstMatch(html) {
            let t = decodeEntities(m[1]).squashed
            return t.isEmpty ? nil : t
        }
        return nil
    }

    public static func siteName(fromHTML html: String) -> String? {
        if let m = Rx("<meta[^>]+property=[\"']og:site_name[\"'][^>]*content=[\"']([^\"']*)[\"']").firstMatch(html), !m[1].isEmpty {
            return decodeEntities(m[1]).squashed
        }
        return nil
    }

    // MARK: schema.org JobPosting

    public struct Posting: Equatable {
        public var title: String?
        public var employer: String?
        public var descriptionHTML: String?
        public var datePosted: Date?
        public var validThrough: Date?
        public var location: String?
        public var remote: Bool = false
        public var salary: SalaryInfo?
        public var employmentType: String?
    }

    public static func jobPostings(fromHTML html: String) -> [Posting] {
        var out: [Posting] = []
        let pattern = Rx("<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>")
        for m in pattern.allMatches(html) {
            let json = m[1].trimmed
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            collect(object, into: &out)
        }
        return out
    }

    static func collect(_ object: Any, into out: inout [Posting]) {
        if let array = object as? [Any] {
            for item in array { collect(item, into: &out) }
            return
        }
        guard let dict = object as? [String: Any] else { return }
        if let graph = dict["@graph"] { collect(graph, into: &out) }
        let type = dict["@type"]
        let isPosting = (type as? String) == "JobPosting" || ((type as? [Any])?.contains { ($0 as? String) == "JobPosting" } ?? false)
        guard isPosting else { return }
        var p = Posting()
        p.title = (dict["title"] as? String).map { decodeEntities($0).squashed }
        p.descriptionHTML = dict["description"] as? String
        p.datePosted = parseDate(dict["datePosted"] as? String)
        p.validThrough = parseDate(dict["validThrough"] as? String)
        if let org = dict["hiringOrganization"] as? [String: Any] {
            p.employer = (org["name"] as? String).map { decodeEntities($0).squashed }
        } else if let org = dict["hiringOrganization"] as? String {
            p.employer = org
        }
        if let t = dict["jobLocationType"] as? String, t.uppercased().contains("TELECOMMUTE") { p.remote = true }
        p.location = locationText(dict["jobLocation"])
        if p.location == nil, let req = dict["applicantLocationRequirements"] {
            if let name = locationName(req) { p.location = p.remote ? "Remote (\(name))" : name }
        }
        if p.remote && p.location == nil { p.location = "Remote" }
        if let e = dict["employmentType"] as? String { p.employmentType = e.replacingOccurrences(of: "_", with: " ").capitalized }
        if let e = dict["employmentType"] as? [String] { p.employmentType = e.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", ") }
        p.salary = salary(dict["baseSalary"])
        out.append(p)
    }

    static func locationText(_ value: Any?) -> String? {
        if let array = value as? [Any] {
            let names = array.compactMap { locationText($0) }
            return names.isEmpty ? nil : Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.joined(separator: "; ")
        }
        guard let dict = value as? [String: Any] else { return value as? String }
        if let address = dict["address"] as? [String: Any] {
            let parts = [address["addressLocality"], address["addressRegion"]].compactMap { $0 as? String }.filter { !$0.trimmed.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
            if let country = address["addressCountry"] as? String { return country }
            if let country = (address["addressCountry"] as? [String: Any])?["name"] as? String { return country }
        }
        if let address = dict["address"] as? String { return address }
        return dict["name"] as? String
    }

    static func locationName(_ value: Any?) -> String? {
        if let array = value as? [Any] { return array.compactMap { locationName($0) }.first }
        if let dict = value as? [String: Any] { return dict["name"] as? String }
        return value as? String
    }

    static func salary(_ value: Any?) -> SalaryInfo? {
        guard let dict = value as? [String: Any] else { return nil }
        let currency = (dict["currency"] as? String) ?? "USD"
        var minimum: Double?, maximum: Double?, unit = "YEAR"
        if let v = dict["value"] as? [String: Any] {
            minimum = number(v["minValue"]) ?? number(v["value"])
            maximum = number(v["maxValue"]) ?? number(v["value"])
            unit = (v["unitText"] as? String) ?? unit
        } else {
            minimum = number(dict["value"])
            maximum = minimum
        }
        guard minimum != nil || maximum != nil else { return nil }
        let period: PayPeriod
        switch unit.uppercased() {
        case "HOUR": period = .hour
        case "DAY": period = .day
        case "WEEK": period = .week
        case "MONTH": period = .month
        default: period = .year
        }
        let info = SalaryInfo(minimum: minimum, maximum: maximum, currency: currency, period: period, text: "", source: "Job posting data")
        var withText = info
        withText.text = info.display
        return withText
    }

    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: "")) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    public static func parseDate(_ s: String?) -> Date? {
        guard let s = s?.trimmed, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options in [ISO8601DateFormatter.Options.withInternetDateTime,
                        [.withInternetDateTime, .withFractionalSeconds],
                        [.withFullDate]] {
            iso.formatOptions = options
            if let d = iso.date(from: s) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy", "MMMM d, yyyy", "MMM d, yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        if s.count >= 10, let d = iso.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    // MARK: Page problems

    public enum PageIssue: Equatable {
        /// The site wants a sign-in before showing the posting.
        case signInRequired
        /// The site is checking for automated visitors.
        case botCheck
        /// Not much text came back (pages built entirely by JavaScript).
        case tooLittleText
    }

    public static func issue(html: String, text: String) -> PageIssue? {
        let lower = text.lowercased()
        let htmlLower = html.prefix(200_000).lowercased()
        let botCues = ["verify you are human", "are you a robot", "captcha", "checking your browser", "just a moment...",
                       "cf-challenge", "access denied", "unusual traffic", "please enable cookies", "request blocked",
                       "pardon our interruption"]
        if botCues.contains(where: { lower.contains($0) }) || htmlLower.contains("cf-chl") || htmlLower.contains("g-recaptcha") {
            return .botCheck
        }
        let signInCues = ["sign in to view", "sign in to see", "log in to view", "log in to see", "join now to see",
                          "authwall", "please sign in", "please log in", "you must be logged in", "login required",
                          "sign in to continue", "sign in to apply"]
        if signInCues.contains(where: { lower.contains($0) || htmlLower.contains($0) }) && text.count < 4000 {
            return .signInRequired
        }
        if text.count < 300 { return .tooLittleText }
        return nil
    }

    /// Words on a page that mean the posting has closed.
    public static func closedCue(in text: String) -> String? {
        let lower = text.lowercased()
        let cues = ["no longer accepting applications", "this job is no longer available", "this position has been filled",
                    "position has been filled", "this job has expired", "job posting has expired", "this posting is closed",
                    "this job is closed", "no longer open", "job is no longer active", "this requisition is closed",
                    "the job you are looking for is no longer", "this position is no longer available"]
        return cues.first { lower.contains($0) }
    }
}
