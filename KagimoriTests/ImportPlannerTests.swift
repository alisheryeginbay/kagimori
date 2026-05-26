import XCTest
@testable import Kagimori

final class ImportPlannerTests: XCTestCase {
    private func existing(_ key: String, _ issuer: String, _ name: String, _ secret: String?) -> ImportPlanner.ExistingAccount {
        ImportPlanner.ExistingAccount(keychainKey: key, issuer: issuer, accountName: name, secret: secret)
    }

    func testSkipsWhenSecretAlreadyStored() {
        let rows = [existing("k1", "npm", "me@x.com", "JBSWY3DP")]
        let action = ImportPlanner.action(forSecret: "jbswy3dp", issuer: "npm", accountName: "me@x.com", existing: rows)
        XCTAssertEqual(action, .skip)
    }

    func testRestoresSecretlessRowByIssuerAndName() {
        let rows = [existing("k1", "npm", "me@x.com", nil)]
        let action = ImportPlanner.action(forSecret: "JBSWY3DP", issuer: " NPM ", accountName: "ME@X.COM", existing: rows)
        XCTAssertEqual(action, .restore(keychainKey: "k1"))
    }

    func testAddsWhenNoMatch() {
        let rows = [existing("k1", "github", "me@x.com", "AAAA")]
        let action = ImportPlanner.action(forSecret: "JBSWY3DP", issuer: "npm", accountName: "me@x.com", existing: rows)
        XCTAssertEqual(action, .add)
    }

    func testSecretMatchTakesPriorityOverNameMatch() {
        let rows = [
            existing("k1", "npm", "me@x.com", "JBSWY3DP"),
            existing("k2", "npm", "me@x.com", nil),
        ]
        let action = ImportPlanner.action(forSecret: "JBSWY3DP", issuer: "npm", accountName: "me@x.com", existing: rows)
        XCTAssertEqual(action, .skip)
    }
}
