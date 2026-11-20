import Foundation

/// Line-by-line comparison for version history.
public enum LineDiff {
    public enum Change: Equatable, Hashable {
        case same(String)
        case added(String)
        case removed(String)
    }

    public static func compare(_ old: String, _ new: String) -> [Change] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let n = a.count, m = b.count
        // Longest common subsequence table (resumes are short, so O(n·m) is fine).
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var out: [Change] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                out.append(.same(a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                out.append(.removed(a[i])); i += 1
            } else {
                out.append(.added(b[j])); j += 1
            }
        }
        while i < n { out.append(.removed(a[i])); i += 1 }
        while j < m { out.append(.added(b[j])); j += 1 }
        return out
    }

    public static func summary(_ changes: [Change]) -> String {
        let added = changes.filter { if case .added(let s) = $0 { return !s.trimmed.isEmpty }; return false }.count
        let removed = changes.filter { if case .removed(let s) = $0 { return !s.trimmed.isEmpty }; return false }.count
        if added == 0 && removed == 0 { return "No differences" }
        return "\(added) line\(added == 1 ? "" : "s") added, \(removed) removed"
    }
}

/// Version numbers and GitHub Releases.
public enum Releases {
    public struct Release: Equatable {
        public var version: String
        public var tag: String
        public var name: String
        public var notes: String
        public var published: Date?
        public var htmlURL: String
        public var zipballURL: String
        public var assets: [Asset]

        /// The prebuilt app attached to the release, if any.
        public var appAsset: Asset? {
            assets.first { $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().contains("job") && !$0.name.lowercased().contains("source") }
                ?? assets.first { $0.name.lowercased().hasSuffix(".app.zip") }
        }
    }

    public struct Asset: Equatable {
        public var name: String
        /// API URL (works for private repositories with a token and Accept: application/octet-stream).
        public var apiURL: String
        public var downloadURL: String
        public var size: Int
    }

    public static func parse(_ data: Data) throws -> Release {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "JobBot", code: 1, userInfo: [NSLocalizedDescriptionKey: "GitHub sent an unexpected reply."])
        }
        let tag = (obj["tag_name"] as? String) ?? ""
        let assets = (obj["assets"] as? [[String: Any]] ?? []).map { a in
            Asset(name: (a["name"] as? String) ?? "", apiURL: (a["url"] as? String) ?? "",
                  downloadURL: (a["browser_download_url"] as? String) ?? "", size: (a["size"] as? Int) ?? 0)
        }
        return Release(version: version(fromTag: tag), tag: tag, name: (obj["name"] as? String) ?? tag,
                       notes: (obj["body"] as? String) ?? "", published: HTMLText.parseDate(obj["published_at"] as? String),
                       htmlURL: (obj["html_url"] as? String) ?? "", zipballURL: (obj["zipball_url"] as? String) ?? "",
                       assets: assets)
    }

    /// "v1.2.0" → "1.2.0"
    public static func version(fromTag tag: String) -> String {
        var t = tag.trimmed
        if t.lowercased().hasPrefix("v") { t.removeFirst() }
        return t
    }

    /// True when a is a newer version than b ("1.10" > "1.9").
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = numbers(a), y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func numbers(_ v: String) -> [Int] {
        let core = v.split(separator: "-").first.map(String.init) ?? v
        return core.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
    }
}
