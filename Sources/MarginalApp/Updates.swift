import AppKit
import Sparkle

protocol UpdateControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    func start()
    func checkForUpdates()
}

private final class SparkleUpdates: UpdateControlling {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    func start() { controller.startUpdater() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// Sparkle owns scheduling, download verification, installation, and its persisted preferences.
/// Unpackaged development binaries and builds without a feed never start an updater.
final class UpdateChecker: NSObject, NSMenuItemValidation {
    private let engine: UpdateControlling?
    private var started = false
    var automaticallyChecks: Bool { engine?.automaticallyChecksForUpdates ?? false }
    var automaticallyDownloads: Bool { engine?.automaticallyDownloadsUpdates ?? false }
    var isEnabled: Bool { engine != nil }

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard, engine: UpdateControlling? = nil) {
        let configured = Self.isConfigured(bundle)
        if configured || engine != nil {
            Self.migratePreferences(defaults)
            self.engine = engine ?? SparkleUpdates()
        } else {
            self.engine = nil
        }
        super.init()
    }

    static func isConfigured(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app" &&
        (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.isEmpty == false &&
        (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.isEmpty == false
    }

    static func migratePreferences(_ defaults: UserDefaults) {
        // Carry forward an explicit choice from the GitHub checker once. Later changes belong to Sparkle.
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let previous = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool {
            defaults.set(previous, forKey: "SUEnableAutomaticChecks")
        }
    }

    func start() {
        guard !started, let engine else { return }
        started = true
        engine.start()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let engine, engine.canCheckForUpdates else { return }
        engine.checkForUpdates()
    }

    @objc func toggleAutomaticChecks(_ sender: NSMenuItem) {
        guard let engine else { return }
        engine.automaticallyChecksForUpdates.toggle()
        sender.state = automaticallyChecks ? .on : .off
    }

    @objc func toggleAutomaticDownloads(_ sender: NSMenuItem) {
        guard let engine, engine.automaticallyChecksForUpdates else { return }
        engine.automaticallyDownloadsUpdates.toggle()
        sender.state = automaticallyDownloads ? .on : .off
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) { return engine?.canCheckForUpdates ?? false }
        if menuItem.action == #selector(toggleAutomaticChecks(_:)) {
            menuItem.state = automaticallyChecks ? .on : .off
            return isEnabled
        }
        if menuItem.action == #selector(toggleAutomaticDownloads(_:)) {
            menuItem.state = automaticallyDownloads ? .on : .off
            return isEnabled && automaticallyChecks
        }
        return true
    }
}

/// Read the same feed as the app without showing UI or downloading an update.
final class UpdateProbe: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    func run() {
        guard UpdateChecker.isConfigured(.main) else {
            fail("Run --check-updates from a packaged app with an update feed.")
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.checkForUpdateInformation()
        } catch { fail(error.localizedDescription) }
        // Informational checks use Sparkle's delegate callbacks, without presenting its user interface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.fail("The update feed did not respond within 30 seconds.") }
        RunLoop.main.run()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("Marginal \(item.displayVersionString) is available: \(item.fileURL?.absoluteString ?? "")")
        exit(0)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        print("Marginal \(version) is up to date.")
        exit(0)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { fail(error.localizedDescription) }

    private func fail(_ message: String) -> Never {
        fputs("Update check failed: \(message)\n", stderr)
        exit(1)
    }
}
