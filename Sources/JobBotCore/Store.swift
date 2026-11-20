import Foundation

/// Everything Job Bot keeps, in one JSON file on this Mac.
public struct AppData: Codable, Equatable {
    public var schemaVersion: Int
    public var master: Profile
    public var jobs: [Job]
    public var resumes: [TailoredResume]
    public var letters: [CoverLetter]
    public var versions: [VersionSnapshot]
    public var preferences: Preferences
    public var discovery: DiscoverySettings
    public var pivots: PivotSettings
    public var examplePatterns: [ExamplePatterns]
    /// A record of every time data left this Mac (what, where, when).
    public var activity: [ActivityRecord]
    /// Postings found on company job boards, shown in Jobs › Found (added in 1.0.3; optional so
    /// older libraries still open).
    public var foundListings: FoundListings?

    public var found: FoundListings {
        get { foundListings ?? FoundListings() }
        set { foundListings = newValue }
    }

    public init() {
        schemaVersion = 1
        master = .starter
        jobs = []
        resumes = []
        letters = []
        versions = []
        preferences = Preferences()
        discovery = DiscoverySettings()
        pivots = PivotSettings()
        examplePatterns = []
        activity = []
        foundListings = FoundListings()
    }

    public func job(_ id: UUID?) -> Job? { id.flatMap { id in jobs.first { $0.id == id } } }
    public func resume(_ id: UUID?) -> TailoredResume? { id.flatMap { id in resumes.first { $0.id == id } } }
    public func letter(_ id: UUID?) -> CoverLetter? { id.flatMap { id in letters.first { $0.id == id } } }
}

public struct Preferences: Codable, Equatable {
    public var aiEnabled: Bool
    /// Ask before every request that sends personal information to the AI service.
    public var confirmEachAIRequest: Bool
    public var aiModel: String
    public var fetchJobPages: Bool
    public var publicJobBoards: Bool
    public var defaultTemplate: TemplateID
    public var currentCompensation: Double?
    public var targetCompensation: Double?
    public var checkForUpdates: Bool
    public var updateRepository: String
    public var locations: LocationFilter

    public init() {
        aiEnabled = false
        confirmEachAIRequest = true
        aiModel = "claude-sonnet-5-5"
        fetchJobPages = true
        publicJobBoards = true
        defaultTemplate = .atsSimple
        currentCompensation = nil
        targetCompensation = nil
        checkForUpdates = true
        updateRepository = "guitarherofree/job-bot"
        locations = LocationFilter()
    }
}

public struct ActivityRecord: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    /// "Anthropic (Claude API)", "Greenhouse job board", "Job page at example.com", "GitHub".
    public var service: String
    public var purpose: String
    /// What kinds of information were included ("Profile, job description").
    public var dataSent: String
    public var bytes: Int

    public init(id: UUID = UUID(), date: Date = Date(), service: String, purpose: String, dataSent: String, bytes: Int) {
        self.id = id
        self.date = date
        self.service = service
        self.purpose = purpose
        self.dataSent = dataSent
        self.bytes = bytes
    }
}

/// Loads and saves AppData. Writes are atomic, the previous file is kept as a backup, and the
/// files are readable only by this user account.
public final class DataStore {
    public let folder: URL
    public var file: URL { folder.appendingPathComponent("library.json") }
    public var backup: URL { folder.appendingPathComponent("library.backup.json") }

    public init(folder: URL) {
        self.folder = folder
    }

    public static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Job Bot", isDirectory: true)
    }

    public enum LoadResult {
        case fresh(AppData)
        case loaded(AppData)
        /// The main file couldn't be read; the backup was used. The damaged file was kept.
        case recovered(AppData, String)
        /// Neither file could be read. The files were left untouched.
        case failed(String)
    }

    public func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else {
            if fm.fileExists(atPath: backup.path), let data = try? decode(backup) {
                return .recovered(data, "The library file was missing; the backup was used.")
            }
            return .fresh(AppData())
        }
        do {
            return .loaded(try decode(file))
        } catch {
            let message = error.localizedDescription
            if let data = try? decode(backup) {
                let kept = folder.appendingPathComponent("library.damaged-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: file, to: kept)
                return .recovered(data, "Your library file couldn't be read (\(message)). Job Bot opened the backup and kept the damaged file as \(kept.lastPathComponent).")
            }
            return .failed("Your library file couldn't be read (\(message)). Nothing was changed. The file is at \(file.path).")
        }
    }

    func decode(_ url: URL) throws -> AppData {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: data)
    }

    public func save(_ appData: AppData) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try Self.encoder.encode(appData)
        if fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: file, to: backup)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try data.write(to: file, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Deletes every file Job Bot stored in its folder.
    public func deleteAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
