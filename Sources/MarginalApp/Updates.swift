import AppKit

struct ReleaseVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }

    var description: String { "\(major).\(minor).\(patch)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableUpdate: Equatable {
    let version: ReleaseVersion
    let pageURL: URL
}

enum UpdateError: LocalizedError {
    case invalidRelease, rateLimited, serverError
    var errorDescription: String? {
        switch self {
        case .invalidRelease: return "GitHub returned an unexpected release response. Please try again later."
        case .rateLimited: return "GitHub is temporarily limiting update checks. Please try again later."
        case .serverError: return "GitHub couldn't complete the update check. Please try again later."
        }
    }
}

final class GitHubUpdateService {
    static let endpoint = URL(string: "https://api.github.com/repos/acousland/marginal/releases/latest")!
    let currentVersion: String
    private let session: URLSession

    init(currentVersion: String, session: URLSession? = nil) {
        self.currentVersion = currentVersion
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchLatest(completion: @escaping (Result<AvailableUpdate?, Error>) -> Void) {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Marginal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [currentVersion] data, response, error in
            if let error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse else { completion(.failure(UpdateError.serverError)); return }
            // A new repository may not have a published stable release yet.
            if response.statusCode == 404 { completion(.success(nil)); return }
            if response.statusCode == 403 || response.statusCode == 429 { completion(.failure(UpdateError.rateLimited)); return }
            guard response.statusCode == 200, let data else { completion(.failure(UpdateError.serverError)); return }
            do { completion(.success(try Self.update(from: data, currentVersion: currentVersion))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let size: Int
        let state: String
        let browser_download_url: URL
    }

    static func update(from data: Data, currentVersion: String) throws -> AvailableUpdate? {
        guard let current = ReleaseVersion(currentVersion) else { throw UpdateError.invalidRelease }
        let release: Release
        do { release = try JSONDecoder().decode(Release.self, from: data) }
        catch { throw UpdateError.invalidRelease }
        guard !release.draft, !release.prerelease, let version = ReleaseVersion(release.tag_name) else { return nil }
        guard version > current else { return nil }
        let expectedPage = URL(string: "https://github.com/acousland/marginal/releases/tag/")!.appendingPathComponent(release.tag_name)
        guard release.html_url == expectedPage else { throw UpdateError.invalidRelease }
        let displayVersion = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let expectedArchive = URL(string: "https://github.com/acousland/marginal/releases/download/")!.appendingPathComponent(release.tag_name).appendingPathComponent("Marginal-\(displayVersion)-macOS.zip")
        guard release.assets.contains(where: {
            $0.name == "Marginal-\(displayVersion)-macOS.zip" && $0.size > 0 && $0.state == "uploaded" &&
            $0.browser_download_url == expectedArchive
        }) else { throw UpdateError.invalidRelease }
        return AvailableUpdate(version: version, pageURL: release.html_url)
    }


}

final class UpdateChecker: NSObject, NSMenuItemValidation {
    enum Notice {
        case available(AvailableUpdate), upToDate, failed(Error)
    }
    static let automaticKey = "automaticallyChecksForUpdates"
    static let lastAttemptKey = "lastUpdateCheck"
    static let notifiedKey = "lastNotifiedUpdateVersion"
    static let interval: TimeInterval = 24 * 60 * 60

    let currentVersion: String
    private let defaults: UserDefaults
    private let fetch: (@escaping (Result<AvailableUpdate?, Error>) -> Void) -> Void
    private let clock: () -> Date
    private let isActive: () -> Bool
    private let notice: ((Notice) -> Void)?
    private var timer: Timer?
    private(set) var isChecking = false
    private var manualRequest = false
    private var pendingUpdate: AvailableUpdate?
    weak var checkMenuItem: NSMenuItem?

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         defaults: UserDefaults = .standard,
         fetch: ((@escaping (Result<AvailableUpdate?, Error>) -> Void) -> Void)? = nil,
         clock: @escaping () -> Date = Date.init,
         isActive: @escaping () -> Bool = { NSApp?.isActive ?? false },
         notice: ((Notice) -> Void)? = nil) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.clock = clock
        self.isActive = isActive
        self.notice = notice
        let service = GitHubUpdateService(currentVersion: currentVersion)
        self.fetch = fetch ?? service.fetchLatest
        defaults.register(defaults: [Self.automaticKey: true])
        super.init()
    }

    deinit { timer?.invalidate() }
    var automaticallyChecks: Bool { defaults.bool(forKey: Self.automaticKey) }

    func start() {
        restartTimer()
        // Keep launch and the first document's rendering independent of networking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.checkAutomaticallyIfNeeded() }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        if automaticallyChecks {
            timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.checkAutomaticallyIfNeeded() }
            timer?.tolerance = 60
        }
    }

    func checkAutomaticallyIfNeeded() {
        guard automaticallyChecks, !isChecking else { return }
        if let last = defaults.object(forKey: Self.lastAttemptKey) as? Date {
            let elapsed = clock().timeIntervalSince(last)
            if elapsed >= 0 && elapsed < Self.interval { return }
        }
        check(manual: false)
    }

    @objc func checkForUpdates(_ sender: Any?) { check(manual: true) }

    @objc func toggleAutomaticChecks(_ sender: NSMenuItem) {
        defaults.set(!automaticallyChecks, forKey: Self.automaticKey)
        sender.state = automaticallyChecks ? .on : .off
        restartTimer()
        if automaticallyChecks { checkAutomaticallyIfNeeded() }
        else { pendingUpdate = nil }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) { return !isChecking }
        if menuItem.action == #selector(toggleAutomaticChecks(_:)) { menuItem.state = automaticallyChecks ? .on : .off }
        return true
    }

    private func check(manual: Bool) {
        if isChecking {
            // If the user asks during a background check, show that check's result.
            manualRequest = manualRequest || manual
            return
        }
        isChecking = true
        manualRequest = manual
        checkMenuItem?.title = "Checking for Updates…"
        defaults.set(clock(), forKey: Self.lastAttemptKey)
        fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.checkMenuItem?.title = "Check for Updates…"
                let manual = self.manualRequest
                self.manualRequest = false
                switch result {
                case .success(let update):
                    if let update {
                        guard manual || self.automaticallyChecks else { return }
                        if manual || self.defaults.string(forKey: Self.notifiedKey) != update.version.description {
                            if !manual && !self.isActive() { self.pendingUpdate = update; return }
                            self.pendingUpdate = nil
                            self.notify(update)
                        }
                    } else {
                        self.pendingUpdate = nil
                        if manual { self.present(.upToDate) }
                    }
                case .failure(let error):
                    if manual { self.present(.failed(error)) }
                }
            }
        }
    }

    func showPendingUpdate() {
        guard automaticallyChecks, isActive(), let update = pendingUpdate else { return }
        pendingUpdate = nil
        if defaults.string(forKey: Self.notifiedKey) != update.version.description { notify(update) }
    }

    private func notify(_ update: AvailableUpdate) {
        defaults.set(update.version.description, forKey: Self.notifiedKey)
        present(.available(update))
    }

    private func present(_ result: Notice) {
        if let notice { notice(result); return }
        let alert = NSAlert()
        var download: URL?
        switch result {
        case .available(let update):
            alert.messageText = "Marginal \(update.version) Is Available"
            alert.informativeText = "You're using Marginal \(currentVersion). Download the new version from GitHub, then replace Marginal in Applications."
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Later")
            download = update.pageURL
        case .upToDate:
            alert.messageText = "You're Up to Date"
            alert.informativeText = "Marginal \(currentVersion) is up to date."
            alert.addButton(withTitle: "OK")
        case .failed(let error):
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Check for Updates"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
        }
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn, let download { NSWorkspace.shared.open(download) }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
}
