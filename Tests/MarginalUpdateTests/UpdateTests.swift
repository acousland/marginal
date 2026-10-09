import XCTest
import AppKit
@testable import MarginalApp

private final class TestUpdater: UpdateControlling {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = false
    var starts = 0
    var checks = 0
    func start() { starts += 1 }
    func checkForUpdates() { checks += 1 }
}

final class UpdateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "Marginal.UpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDevelopmentBinaryDoesNotStartAnUpdaterOrMigratePreferences() {
        defaults.set(false, forKey: "automaticallyChecksForUpdates")
        let checker = UpdateChecker(defaults: defaults)
        checker.start()
        XCTAssertFalse(checker.isEnabled)
        XCTAssertFalse(UpdateChecker.isConfigured(.main))
        XCTAssertNil(defaults.object(forKey: "SUEnableAutomaticChecks"))
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(UpdateChecker.checkForUpdates(_:)), keyEquivalent: "")
        XCTAssertFalse(checker.validateMenuItem(item))
    }

    func testLegacyOptOutIsPreservedWithoutOverwritingNewPreferences() {
        defaults.set(false, forKey: "automaticallyChecksForUpdates")
        UpdateChecker.migratePreferences(defaults)
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        UpdateChecker.migratePreferences(defaults)
        XCTAssertTrue(defaults.bool(forKey: "SUEnableAutomaticChecks"))
    }

    func testNewInstallationLeavesSparkleDefaultsAlone() {
        UpdateChecker.migratePreferences(defaults)
        XCTAssertNil(defaults.object(forKey: "SUEnableAutomaticChecks"))
        XCTAssertNil(defaults.object(forKey: "SUAutomaticallyUpdate"))
    }

    func testStartsOnceAndManualCheckRemainsAvailableAfterOptOut() {
        let engine = TestUpdater()
        engine.automaticallyChecksForUpdates = false
        let checker = UpdateChecker(defaults: defaults, engine: engine)
        checker.start()
        checker.start()
        XCTAssertEqual(engine.starts, 1)
        checker.checkForUpdates(nil)
        XCTAssertEqual(engine.checks, 1)
        engine.canCheckForUpdates = false
        checker.checkForUpdates(nil)
        XCTAssertEqual(engine.checks, 1)
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(UpdateChecker.checkForUpdates(_:)), keyEquivalent: "")
        XCTAssertFalse(checker.validateMenuItem(item))
        engine.canCheckForUpdates = true
        XCTAssertTrue(checker.validateMenuItem(item))
    }

    func testMenuSettingsTrackSparkleAndAutomaticInstallRequiresChecks() {
        let engine = TestUpdater()
        let checker = UpdateChecker(defaults: defaults, engine: engine)
        let checks = NSMenuItem(title: "Automatically Check for Updates", action: #selector(UpdateChecker.toggleAutomaticChecks(_:)), keyEquivalent: "")
        let downloads = NSMenuItem(title: "Download and Install Updates Automatically", action: #selector(UpdateChecker.toggleAutomaticDownloads(_:)), keyEquivalent: "")
        XCTAssertTrue(checker.validateMenuItem(checks))
        XCTAssertEqual(checks.state, .on)
        XCTAssertTrue(checker.validateMenuItem(downloads))
        XCTAssertEqual(downloads.state, .off)
        checker.toggleAutomaticDownloads(downloads)
        XCTAssertTrue(engine.automaticallyDownloadsUpdates)
        XCTAssertEqual(downloads.state, .on)
        checker.toggleAutomaticChecks(checks)
        XCTAssertFalse(engine.automaticallyChecksForUpdates)
        XCTAssertEqual(checks.state, .off)
        XCTAssertFalse(checker.validateMenuItem(downloads))
        checker.toggleAutomaticDownloads(downloads)
        XCTAssertTrue(engine.automaticallyDownloadsUpdates)
        checker.toggleAutomaticChecks(checks)
        XCTAssertTrue(checker.validateMenuItem(downloads))
        // A preference changed through Sparkle's own UI also updates the menu.
        engine.automaticallyDownloadsUpdates = false
        XCTAssertTrue(checker.validateMenuItem(downloads))
        XCTAssertEqual(downloads.state, .off)
    }
}
