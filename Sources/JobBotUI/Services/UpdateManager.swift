import Foundation
import AppKit
import JobBotCore

/// Updates from GitHub Releases, without Terminal.
///
/// 1. Check: asks GitHub for the latest release and shows its version and notes.
/// 2. Download: fetches the app attached to the release in the background, unpacks it and
///    checks it's really Job Bot at the expected version.
/// 3. Install: when you click Restart (or quit), a small helper waits for Job Bot to close,
///    swaps in the new copy and reopens it. Problems are reported on the next launch.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(Releases.Release)
        case downloading(Releases.Release, Double)
        case ready(Releases.Release, URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var lastChecked: Date?
    /// Called to record network activity in the privacy log.
    var record: (@MainActor (ActivityRecord) -> Void)?

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.guitarherofree.jobbot" }

    /// Updates only work for the installed app (not when run from a build folder by `swift run`).
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private var folder: URL { DataStore.defaultFolder.appendingPathComponent("Updates", isDirectory: true) }
    private var statusFile: URL { folder.appendingPathComponent("install-status") }
    private var task: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    // MARK: Launch

    /// Reports the result of an install that happened while the app was closed.
    func launchReport() -> String? {
        guard let text = try? String(contentsOf: statusFile, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: statusFile)
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            if let eq = line.firstIndex(of: "=") { fields[String(line[..<eq])] = String(line[line.index(after: eq)...]) }
        }
        switch fields["state"] {
        case "done":
            let v = fields["version"] ?? Self.appVersion
            return v == Self.appVersion ? "Job Bot was updated to version \(v)." : nil
        case "failed":
            return "The last update didn't install: \(fields["message"] ?? "unknown problem"). You're still on version \(Self.appVersion)."
        default:
            return nil
        }
    }

    // MARK: Check

    func check(repository: String, automaticDownload: Bool) async {
        if case .downloading = phase { return }
        let repo = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repo.split(separator: "/").count == 2, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            phase = .failed("The update repository should look like owner/name. Check Settings › Updates.")
            return
        }
        phase = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("JobBot/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")
        if let token = Keychain.get(.githubToken) { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            record?(ActivityRecord(service: "GitHub", purpose: "Check for app updates", dataSent: "App version only", bytes: 0))
            lastChecked = Date()
            switch code {
            case 200:
                let release = try Releases.parse(data)
                if Releases.isNewer(release.version, than: Self.appVersion) {
                    phase = .available(release)
                    if automaticDownload && canInstall && release.appAsset != nil { download(release) }
                } else {
                    phase = .upToDate(Self.appVersion)
                }
            case 401:
                phase = .failed("GitHub didn't accept the access token. Update it in Settings › Updates.")
            case 404:
                phase = .failed(Keychain.has(.githubToken)
                    ? "No published release was found in \(repo), or the token can't read it."
                    : "No release was found. If \(repo) is private, add a GitHub token in Settings › Updates.")
            case 403, 429:
                phase = .failed("GitHub is limiting requests right now. Try again later.")
            default:
                phase = .failed("GitHub answered with an error (\(code)).")
            }
        } catch {
            phase = .failed("Couldn't reach GitHub: \(error.localizedDescription)")
        }
    }

    // MARK: Download

    func download(_ release: Releases.Release) {
        guard canInstall else {
            phase = .failed("Updates install only into the Job Bot app in Applications (not a development build).")
            return
        }
        guard let asset = release.appAsset, let url = URL(string: asset.apiURL.isEmpty ? asset.downloadURL : asset.apiURL) else {
            phase = .failed("Release \(release.version) doesn't include the app file, so it can't be installed automatically. Download it from \(release.htmlURL).")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("JobBot/\(Self.appVersion)", forHTTPHeaderField: "User-Agent")
        if let token = Keychain.get(.githubToken) { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        phase = .downloading(release, 0)
        let session = URLSession(configuration: .default, delegate: RedirectStripper(), delegateQueue: nil)
        let task = session.downloadTask(with: request) { [weak self] location, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var moved: URL?
            if let location, error == nil, code == 200 {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("JobBot-\(release.version)-\(UUID().uuidString).zip")
                if (try? FileManager.default.moveItem(at: location, to: tmp)) != nil { moved = tmp }
            }
            let message: String? = error?.localizedDescription ?? (code == 200 ? nil : "GitHub answered with an error (\(code)).")
            Task { @MainActor in
                self?.finishDownload(release: release, zip: moved, error: message)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let fraction = p.fractionCompleted
            Task { @MainActor in
                guard let self, case .downloading(let r, _) = self.phase else { return }
                self.phase = .downloading(r, fraction)
            }
        }
        self.task = task
        task.resume()
        record?(ActivityRecord(service: "GitHub", purpose: "Download Job Bot \(release.version)", dataSent: "Nothing personal", bytes: 0))
    }

    private func finishDownload(release: Releases.Release, zip: URL?, error: String?) {
        progressObservation = nil
        task = nil
        guard let zip else {
            phase = .failed("The download failed: \(error ?? "unknown error").")
            return
        }
        do {
            let fm = FileManager.default
            let dest = folder.appendingPathComponent(release.version, isDirectory: true)
            try? fm.removeItem(at: dest)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, dest.path]
            try ditto.run()
            ditto.waitUntilExit()
            try? fm.removeItem(at: zip)
            guard ditto.terminationStatus == 0 else { throw UpdateError("The downloaded file couldn't be unpacked.") }
            guard let app = try fm.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                  let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
                throw UpdateError("The download didn't contain the Job Bot app.")
            }
            guard (info["CFBundleIdentifier"] as? String) == Self.bundleID else {
                throw UpdateError("The downloaded app isn't Job Bot (unexpected identifier), so it wasn't installed.")
            }
            let version = (info["CFBundleShortVersionString"] as? String) ?? ""
            guard version == release.version else {
                throw UpdateError("The downloaded app is version \(version), not \(release.version) as the release says.")
            }
            phase = .ready(release, app)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    // MARK: Install

    /// Quits, installs the downloaded version and reopens.
    func restartToInstall() {
        guard case .ready(_, let app) = phase else { return }
        if launchInstaller(newApp: app, relaunch: true) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NSApp.terminate(nil)
            }
        }
    }

    /// Installs a downloaded update when the app quits (without reopening it).
    func installOnQuitIfReady() {
        guard case .ready(_, let app) = phase else { return }
        _ = launchInstaller(newApp: app, relaunch: false)
    }

    private func launchInstaller(newApp: URL, relaunch: Bool) -> Bool {
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) || fm.isWritableFile(atPath: target.path) else {
            phase = .failed("Job Bot can't replace itself in \(parent.path) (no permission). Move Job Bot to your Applications folder and try again.")
            return false
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let script = folder.appendingPathComponent("install-update.sh")
            try Self.installerScript.write(to: script, atomically: true, encoding: .utf8)
            let version = (NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) ?? ""
            let args = [script.path, newApp.path, target.path, String(ProcessInfo.processInfo.processIdentifier), statusFile.path,
                        relaunch ? "1" : "0", version]
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = args
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            return true
        } catch {
            phase = .failed("Couldn't start the installer: \(error.localizedDescription)")
            return false
        }
    }

    /// Waits for Job Bot to quit, replaces the app in place (so Dock items keep working), and
    /// writes the result for the next launch.
    static let installerScript = """
    #!/bin/bash
    NEW="$1"; TARGET="$2"; PID="$3"; STATUS="$4"; RELAUNCH="$5"; VERSION="$6"
    report() { printf 'state=%s\\nversion=%s\\nmessage=%s\\n' "$1" "$VERSION" "$2" > "$STATUS"; }
    # The app quits first; give it up to 30 seconds.
    for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
    if kill -0 "$PID" 2>/dev/null; then report failed "Job Bot didn't quit in time"; exit 1; fi
    if [ ! -d "$NEW/Contents" ]; then report failed "The downloaded app is missing"; exit 1; fi
    /usr/bin/xattr -dr com.apple.quarantine "$NEW" 2>/dev/null
    if ! /usr/bin/rsync -a --delete "$NEW/" "$TARGET/"; then
      report failed "Copying the new version into place failed"
      [ "$RELAUNCH" = "1" ] && /usr/bin/open "$TARGET"
      exit 1
    fi
    /usr/bin/touch "$TARGET"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" >/dev/null 2>&1
    report done ""
    rm -rf "$(dirname "$NEW")"
    [ "$RELAUNCH" = "1" ] && /usr/bin/open "$TARGET"
    exit 0
    """
}

struct UpdateError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// GitHub serves release files from a storage host after a redirect; the GitHub token must not
/// be sent there.
final class RedirectStripper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        if let host = request.url?.host, host != "api.github.com" {
            r.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(r)
    }
}
