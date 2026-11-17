import XCTest
@testable import ThoughtVault

@MainActor
final class UpdateCheckServiceTests: XCTestCase {
    func testOnlyNewerValidVersionsAreOffered() {
        XCTAssertTrue(UpdateCheckService.Installer.isNewer("1.0.330", than: "1.0.329"))
        XCTAssertTrue(UpdateCheckService.Installer.isNewer("1.1.0", than: "1.0.999"))
        for remote in ["1.0.242", "1.0.329", "", "1.0", "1.0.-1", "1.0.x", "1.0.330-beta", "1.0.330.1"] {
            XCTAssertFalse(UpdateCheckService.Installer.isNewer(remote, than: "1.0.329"), remote)
        }
    }
    func testInstallerURLCannotEscapeThePrivateDirectory() {
        let valid = UpdateCheckService.Installer(version: "1.0.330", filename: "ThoughtVault-1.0.330.dmg")
        XCTAssertEqual(valid.url?.deletingLastPathComponent(), UpdateCheckService.Installer.baseURL)
        for filename in ["../secret.dmg", "https://evil.test/a.dmg", "a.msi", "a.dmg?token=1", "a%2Fdmg", "a/b.dmg"] {
            XCTAssertNil(UpdateCheckService.Installer(version: "1.0.330", filename: filename).url, filename)
        }
    }
    func testBusyRecordingCannotStartAnInstaller() async {
        let service = UpdateCheckService()
        service.isBusy = { true }
        service.usesInstallerDownload = true
        service.downloadURL = UpdateCheckService.Installer.baseURL.appendingPathComponent("test.dmg")
        await service.downloadAndOpen()
        XCTAssertFalse(service.isDownloading)
        XCTAssertEqual(service.errorMessage, "Bijwerken kan zodra opnemen en verwerken klaar zijn.")
    }
}

#if os(macOS) && !APP_STORE
private final class UpdateStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension UpdateCheckServiceTests {
    private func fixture() -> UpdateCheckService {
        UpdateStub.status = 200
        UpdateStub.body = Data()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateStub.self]
        let service = UpdateCheckService(session: URLSession(configuration: config))
        service.isBusy = { false }
        return service
    }

    func testMissingSparkleFeedCanStillOfferNewerMacInstaller() async {
        let service = fixture()
        UpdateStub.body = Data(#"{"latest_version":"9.0.0","windows_x64":{"version":"9.0.0","filename":"Windows.msi"},"macos":{"version":"9.0.0","filename":"ThoughtVault.dmg"}}"#.utf8)
        await service.checkForUpdate(force: true)
        XCTAssertEqual(service.availableVersion, "9.0.0")
        XCTAssertTrue(service.usesInstallerDownload)
        XCTAssertEqual(service.downloadURL?.lastPathComponent, "ThoughtVault.dmg")
    }

    func testOldMacInstallerNeverAdvertisesWindowsLatestVersion() async {
        let service = fixture()
        UpdateStub.body = Data(#"{"latest_version":"9.0.0","macos":{"version":"1.0.1","filename":"ThoughtVault-old.dmg"}}"#.utf8)
        await service.checkForUpdate(force: true)
        XCTAssertNil(service.availableVersion)
        XCTAssertNil(service.downloadURL)
    }

    func testDownloadOpensOnlyAfterTheInstallerIsAvailable() async {
        for status in [200, 404, 503] {
            let service = fixture()
            UpdateStub.status = status
            service.usesInstallerDownload = true
            service.downloadURL = UpdateCheckService.Installer.baseURL.appendingPathComponent("ThoughtVault.dmg")
            var opens = 0
            service.openInstaller = { _ in opens += 1; return true }
            await service.downloadAndOpen()
            XCTAssertEqual(opens, status == 200 ? 1 : 0)
            XCTAssertEqual(service.errorMessage == nil, status == 200)
            XCTAssertFalse(service.isDownloading)
        }
    }

    func testOpeningFailureIsVisibleAndRetryable() async {
        let service = fixture()
        service.usesInstallerDownload = true
        service.downloadURL = UpdateCheckService.Installer.baseURL.appendingPathComponent("ThoughtVault.dmg")
        service.openInstaller = { _ in false }
        await service.downloadAndOpen()
        XCTAssertNotNil(service.errorMessage)
        service.openInstaller = { _ in true }
        await service.downloadAndOpen()
        XCTAssertNil(service.errorMessage)
    }
}
#endif
