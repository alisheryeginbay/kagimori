import XCTest
@testable import Kagimori

final class Base32Tests: XCTestCase {
    func testDecodesRFC4648Vector() {
        // BASE32("foobar") == "MZXW6YTBOI======"
        let data = Base32.decode("MZXW6YTBOI")
        XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, "foobar")
    }

    func testRejectsInvalidCharacters() {
        // 0, 1, 8, 9 are not in the base32 alphabet.
        XCTAssertNil(Base32.decode("0189"))
    }

    func testEmptyInputIsNil() {
        XCTAssertNil(Base32.decode(""))
    }
}
