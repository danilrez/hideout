import XCTest
@testable import Hideout

final class UpdateCheckerTests: XCTestCase {
    func testParsesReleaseTagsAndComparesNumericComponents() throws {
        let current = try XCTUnwrap(UpdateVersion("v0.2.9"))
        let newerMinor = try XCTUnwrap(UpdateVersion("0.10.0"))
        let newerMajor = try XCTUnwrap(UpdateVersion("v1.0.0"))

        XCTAssertEqual(current.description, "0.2.9")
        XCTAssertLessThan(current, newerMinor)
        XCTAssertLessThan(newerMinor, newerMajor)
    }

    func testRejectsMalformedAndPrereleaseVersions() {
        XCTAssertNil(UpdateVersion(""))
        XCTAssertNil(UpdateVersion("0.2"))
        XCTAssertNil(UpdateVersion("0.x.3"))
        XCTAssertNil(UpdateVersion("v0.2.3-beta"))
    }

    func testIdenticalVersionIsNotNewer() throws {
        let first = try XCTUnwrap(UpdateVersion("0.2.3"))
        let second = try XCTUnwrap(UpdateVersion("v0.2.3"))

        XCTAssertEqual(first, second)
        XCTAssertFalse(first < second)
        XCTAssertFalse(second < first)
    }

    func testAcceptsGitHubCanonicalLowercaseReleaseURL() throws {
        let url = try XCTUnwrap(
            UpdateChecker.trustedReleaseURL(
                from: "https://github.com/danilrez/hideout/releases/tag/v0.2.4"
            )
        )

        XCTAssertEqual(url.absoluteString, "https://github.com/danilrez/hideout/releases/tag/v0.2.4")
    }
}
