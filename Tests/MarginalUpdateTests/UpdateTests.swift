import XCTest
import AppKit
@testable import MarginalApp

private final class UpdateURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class UpdateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suite = "Marginal.UpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        UpdateURLProtocol.respond = nil
        super.tearDown()
    }

    private func release(_ tag: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false,
                         page: String? = nil, assetURL: String? = nil, hasAsset: Bool = true, size: Int = 1024) throws -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let asset: [String: Any] = ["name": "Marginal-\(version)-macOS.zip", "size": size, "state": "uploaded",
                                   "browser_download_url": assetURL ?? "https://github.com/acousland/marginal/releases/download/\(tag)/Marginal-\(version)-macOS.zip"]
        return try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": page ?? "https://github.com/acousland/marginal/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease, "assets": hasAsset ? [asset] : []
        ])
    }

    private func available() -> AvailableUpdate {
        AvailableUpdate(version: ReleaseVersion("1.2.0")!, pageURL: URL(string: "https://github.com/acousland/marginal/releases/tag/v1.2.0")!)
    }

    func testNumericVersionOrdering() {
        XCTAssertGreaterThan(ReleaseVersion("1.10.0")!, ReleaseVersion("v1.9.9")!)
        XCTAssertGreaterThan(ReleaseVersion("2.0.0")!, ReleaseVersion("1.99.99")!)
        XCTAssertEqual(ReleaseVersion("v1.2"), ReleaseVersion("1.2.0"))
        for value in ["", "1..2", "1.2.3.4", "1.2-beta", "-1.0", "1.a", " 1.0", "1.٢", "999999999999999999999999"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testNewerStableReleaseWithUploadedArchive() throws {
        let update = try GitHubUpdateService.update(from: release(), currentVersion: "1.1.0")
        XCTAssertEqual(update, available())
        XCTAssertNil(try GitHubUpdateService.update(from: release("v1.1.0"), currentVersion: "1.1.0"))
        XCTAssertNil(try GitHubUpdateService.update(from: release("v1.0.1"), currentVersion: "1.1.0"))
        XCTAssertNil(try GitHubUpdateService.update(from: release(draft: true), currentVersion: "1.1.0"))
        XCTAssertNil(try GitHubUpdateService.update(from: release(prerelease: true), currentVersion: "1.1.0"))
        XCTAssertNil(try GitHubUpdateService.update(from: release("v1.2.0-beta"), currentVersion: "1.1.0"))
    }

    func testRejectsMalformedMissingAndForeignDownloads() throws {
        XCTAssertThrowsError(try GitHubUpdateService.update(from: Data("{}".utf8), currentVersion: "1.1.0"))
        XCTAssertThrowsError(try GitHubUpdateService.update(from: release(hasAsset: false), currentVersion: "1.1.0"))
        XCTAssertThrowsError(try GitHubUpdateService.update(from: release(size: 0), currentVersion: "1.1.0"))
        XCTAssertThrowsError(try GitHubUpdateService.update(from: release(page: "https://example.com/update"), currentVersion: "1.1.0"))
        XCTAssertThrowsError(try GitHubUpdateService.update(from: release(assetURL: "https://github.com/other/project/releases/download/v1.2.0/app.zip"), currentVersion: "1.1.0"))
        XCTAssertThrowsError(try GitHubUpdateService.update(from: release(page: "https://github.com/acousland/marginal/releases/tag/v999.0.0"), currentVersion: "1.1.0"))
    }

    func testHTTPCheckAndErrors() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let service = GitHubUpdateService(currentVersion: "1.1.0", session: URLSession(configuration: configuration))
        let data = try release()
        for status in [200, 404, 403, 429, 500] {
            UpdateURLProtocol.respond = { request in
                XCTAssertEqual(request.url, GitHubUpdateService.endpoint)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Marginal/1.1.0")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (status, data)
            }
            let done = expectation(description: "HTTP \(status)")
            service.fetchLatest { result in
                switch (status, result) {
                case (200, .success(let update)): XCTAssertEqual(update, self.available())
                case (404, .success(let update)): XCTAssertNil(update)
                case (403, .failure), (429, .failure), (500, .failure): break
                default: XCTFail("Unexpected result for \(status): \(result)")
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        UpdateURLProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
        let offline = expectation(description: "Offline")
        service.fetchLatest { result in
            guard case .failure(let error) = result else { XCTFail("Expected an offline error"); offline.fulfill(); return }
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            offline.fulfill()
        }
        wait(for: [offline], timeout: 3)
    }

    func testAutomaticCadenceAndOptOut() {
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { _ in fetches += 1 }, clock: { self.now }, isActive: { true }, notice: { _ in XCTFail("No notification expected") })
        XCTAssertTrue(checker.automaticallyChecks)
        defaults.set(now.addingTimeInterval(-UpdateChecker.interval + 1), forKey: UpdateChecker.lastAttemptKey)
        checker.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetches, 0)
        defaults.set(false, forKey: UpdateChecker.automaticKey)
        defaults.removeObject(forKey: UpdateChecker.lastAttemptKey)
        checker.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetches, 0)
        defaults.set(true, forKey: UpdateChecker.automaticKey)
        checker.checkAutomaticallyIfNeeded()
        checker.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(defaults.object(forKey: UpdateChecker.lastAttemptKey) as? Date, now)
    }

    func testManualChecksEvenWithAutomaticChecksDisabled() {
        defaults.set(false, forKey: UpdateChecker.automaticKey)
        defaults.set(now, forKey: UpdateChecker.lastAttemptKey)
        let done = expectation(description: "Manual up-to-date result")
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { $0(.success(nil)) }, isActive: { true }, notice: { result in
            guard case .upToDate = result else { XCTFail("Expected up-to-date result"); done.fulfill(); return }
            done.fulfill()
        })
        checker.checkForUpdates(nil)
        wait(for: [done], timeout: 3)
        XCTAssertFalse(checker.isChecking)
    }

    func testAutomaticNotificationsOncePerVersionButManualCanRepeat() {
        let update = available()
        var notifications = 0
        var done = expectation(description: "First available update")
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { $0(.success(update)) }, clock: { self.now }, isActive: { true }, notice: { result in
            guard case .available(let found) = result else { XCTFail("Expected available update"); return }
            XCTAssertEqual(found, update)
            notifications += 1
            done.fulfill()
        })
        checker.checkAutomaticallyIfNeeded()
        wait(for: [done], timeout: 3)
        XCTAssertEqual(notifications, 1)
        defaults.removeObject(forKey: UpdateChecker.lastAttemptKey)
        checker.checkAutomaticallyIfNeeded()
        let drained = expectation(description: "Background completion")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
        XCTAssertEqual(notifications, 1)
        done = expectation(description: "Manual repeats available update")
        checker.checkForUpdates(nil)
        wait(for: [done], timeout: 3)
        XCTAssertEqual(notifications, 2)
    }

    func testOfflineBackgroundIsQuietAndManualShowsError() {
        let failure = URLError(.notConnectedToInternet)
        var notices = 0
        let shown = expectation(description: "Manual failure")
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { $0(.failure(failure)) }, isActive: { true }, notice: { result in
            guard case .failed = result else { XCTFail("Expected failure"); return }
            notices += 1
            shown.fulfill()
        })
        checker.checkAutomaticallyIfNeeded()
        let drained = expectation(description: "Quiet automatic completion")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
        XCTAssertEqual(notices, 0)
        checker.checkForUpdates(nil)
        wait(for: [shown], timeout: 3)
        XCTAssertEqual(notices, 1)
    }

    func testOptingOutDuringBackgroundCheckSuppressesNotification() {
        var finish: ((Result<AvailableUpdate?, Error>) -> Void)?
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { finish = $0 }, isActive: { true }, notice: { _ in XCTFail("Opted out") })
        checker.checkAutomaticallyIfNeeded()
        defaults.set(false, forKey: UpdateChecker.automaticKey)
        finish?(.success(available()))
        let drained = expectation(description: "Opt-out completion")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
        XCTAssertFalse(checker.isChecking)
        XCTAssertNil(defaults.string(forKey: UpdateChecker.notifiedKey))
    }

    func testBackgroundNotificationWaitsForActiveApp() {
        var active = false
        var notices = 0
        let done = expectation(description: "Foreground notification")
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { $0(.success(self.available())) }, isActive: { active }, notice: { _ in
            notices += 1
            done.fulfill()
        })
        checker.checkAutomaticallyIfNeeded()
        let drained = expectation(description: "Deferred automatic result")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
        XCTAssertEqual(notices, 0)
        XCTAssertNil(defaults.string(forKey: UpdateChecker.notifiedKey))
        active = true
        checker.showPendingUpdate()
        wait(for: [done], timeout: 3)
        checker.showPendingUpdate()
        XCTAssertEqual(notices, 1)
    }

    func testAutomaticSettingIsPersistentAndMenuReflectsIt() {
        defaults.set(now, forKey: UpdateChecker.lastAttemptKey)
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { _ in XCTFail("Recent check should not repeat") }, clock: { self.now })
        let item = NSMenuItem(title: "Automatically Check for Updates", action: #selector(UpdateChecker.toggleAutomaticChecks(_:)), keyEquivalent: "")
        XCTAssertTrue(checker.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        checker.toggleAutomaticChecks(item)
        XCTAssertFalse(checker.automaticallyChecks)
        XCTAssertEqual(item.state, .off)
        let reloaded = UpdateChecker(currentVersion: "1.1.0", defaults: defaults)
        XCTAssertFalse(reloaded.automaticallyChecks)
        checker.toggleAutomaticChecks(item)
        XCTAssertTrue(checker.automaticallyChecks)
        XCTAssertEqual(item.state, .on)
    }

    func testPendingCheckCoalescesAndManualRequestGetsResult() {
        var finish: ((Result<AvailableUpdate?, Error>) -> Void)?
        var fetches = 0
        let done = expectation(description: "Coalesced manual result")
        let checker = UpdateChecker(currentVersion: "1.1.0", defaults: defaults, fetch: { fetches += 1; finish = $0 }, isActive: { true }, notice: { result in
            guard case .upToDate = result else { XCTFail("Expected result"); return }
            done.fulfill()
        })
        checker.checkAutomaticallyIfNeeded()
        checker.checkForUpdates(nil)
        XCTAssertEqual(fetches, 1)
        finish?(.success(nil))
        wait(for: [done], timeout: 3)
    }
}
