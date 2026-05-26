import XCTest
@testable import Kagimori

final class TwoFASRoundTripTests: XCTestCase {
    func testExportThenImportPreservesAccounts() throws {
        let accounts = [
            TwoFASExporter.ExportAccount(
                issuer: "npm", accountName: "me@x.com", secret: "JBSWY3DP",
                algorithm: .sha1, digits: 6, period: 30
            ),
            TwoFASExporter.ExportAccount(
                issuer: "GitHub", accountName: "octocat", secret: "MZXW6YTBOI",
                algorithm: .sha256, digits: 8, period: 60
            ),
        ]

        let data = try TwoFASExporter.makeBackup(from: accounts)
        let parsed = try TwoFASImporter.parse(data: data)

        XCTAssertEqual(parsed.count, 2)

        let npm = try XCTUnwrap(parsed.first { $0.issuer == "npm" })
        XCTAssertEqual(npm.accountName, "me@x.com")
        XCTAssertEqual(npm.secret, "JBSWY3DP")
        XCTAssertEqual(npm.algorithm, .sha1)
        XCTAssertEqual(npm.digits, 6)
        XCTAssertEqual(npm.period, 30)

        let gh = try XCTUnwrap(parsed.first { $0.issuer == "GitHub" })
        XCTAssertEqual(gh.accountName, "octocat")
        XCTAssertEqual(gh.secret, "MZXW6YTBOI")
        XCTAssertEqual(gh.algorithm, .sha256)
        XCTAssertEqual(gh.digits, 8)
        XCTAssertEqual(gh.period, 60)
    }
}
