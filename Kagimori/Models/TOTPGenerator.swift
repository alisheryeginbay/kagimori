import CryptoKit
import Foundation

enum TOTPGenerator {
    static func generate(
        secret: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        date: Date = .now
    ) -> String {
        guard let secretData = Base32.decode(secret) else {
            return String(repeating: "\u{2013}", count: digits)
        }

        let counter = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: 8)
        let key = SymmetricKey(data: secretData)

        let hmac: Data
        switch algorithm {
        case .sha1:
            hmac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            hmac = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            hmac = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let binary =
            (UInt32(hmac[offset]) & 0x7f) << 24
            | UInt32(hmac[offset + 1]) << 16
            | UInt32(hmac[offset + 2]) << 8
            | UInt32(hmac[offset + 3])

        let otp = binary % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    static func timeRemaining(period: Int = 30, date: Date = .now) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }
}
