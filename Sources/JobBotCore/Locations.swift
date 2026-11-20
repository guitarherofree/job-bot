import Foundation

public struct LocationOption: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var selected: Bool
    public var builtIn: Bool
    /// Other ways postings write it ("NYC", "New York, NY").
    public var aliases: [String]

    public init(id: UUID = UUID(), name: String, selected: Bool = true, builtIn: Bool = false, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.selected = selected
        self.builtIn = builtIn
        self.aliases = aliases
    }

    public var isRemote: Bool { name.lowercased() == "remote" }

    /// Does a posting's location text fall under this option?
    public func matches(_ locationText: String) -> Bool {
        let text = " " + TextTools.words(locationText).joined(separator: " ") + " "
        for term in [name] + aliases {
            let needle = " " + TextTools.words(term).joined(separator: " ") + " "
            if needle.count > 2 && text.contains(needle) { return true }
        }
        if isRemote {
            for cue in [" work from home ", " wfh ", " anywhere ", " distributed ", " telecommute "] where text.contains(cue) {
                return true
            }
        }
        return false
    }
}

/// Location filters for job results. Remote, Atlanta and New York start checked.
public struct LocationFilter: Codable, Equatable, Hashable {
    public var options: [LocationOption]
    /// Show postings that don't list a location (they can't be sorted either way).
    public var includeUnlisted: Bool

    public init() {
        options = [
            LocationOption(name: "Remote", builtIn: true, aliases: ["Remote-first", "Fully remote", "Remote, US", "US Remote"]),
            LocationOption(name: "Atlanta", builtIn: true, aliases: ["Atlanta, GA", "ATL", "Atlanta, Georgia"]),
            LocationOption(name: "New York", builtIn: true, aliases: ["New York, NY", "NYC", "New York City", "Manhattan", "Brooklyn"]),
        ]
        includeUnlisted = true
    }

    public var allSelected: Bool { !options.isEmpty && options.allSatisfy { $0.selected } }

    public mutating func setAll(_ on: Bool) {
        for i in options.indices { options[i].selected = on }
    }

    public var active: [LocationOption] { options.filter { $0.selected } }

    /// Adds a custom location (selected). Returns false when it's already there.
    @discardableResult
    public mutating func add(_ name: String) -> Bool {
        let n = name.trimmed
        guard !n.isEmpty, !options.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return false }
        options.append(LocationOption(name: n, selected: true))
        return true
    }

    public mutating func remove(_ id: UUID) {
        options.removeAll { $0.id == id && !$0.builtIn }
    }

    /// A posting passes when its location matches any checked option. "All" checks every option.
    public func accepts(_ job: Job) -> Bool {
        let text = job.locationForFiltering
        if text.trimmed.isEmpty { return includeUnlisted }
        return active.contains { $0.matches(text) }
    }

    public func accepts(locationText: String) -> Bool {
        if locationText.trimmed.isEmpty { return includeUnlisted }
        return active.contains { $0.matches(locationText) }
    }

    /// "Remote, Atlanta, New York".
    public var summary: String {
        let names = active.map { $0.name }
        return names.isEmpty ? "No locations selected" : names.joined(separator: ", ")
    }
}
