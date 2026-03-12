import Foundation

enum Base32 {
    private static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func decode(_ input: String) -> Data? {
        let cleaned = input.uppercased().filter { $0 != "=" && $0 != " " && $0 != "-" }
        guard !cleaned.isEmpty else { return nil }

        var output = Data()
        var buffer: UInt64 = 0
        var bitsLeft = 0

        for char in cleaned {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let value = UInt64(alphabet.distance(from: alphabet.startIndex, to: index))
            buffer = (buffer << 5) | value
            bitsLeft += 5

            if bitsLeft >= 8 {
                bitsLeft -= 8
                output.append(UInt8((buffer >> bitsLeft) & 0xff))
            }
        }

        return output
    }
}
