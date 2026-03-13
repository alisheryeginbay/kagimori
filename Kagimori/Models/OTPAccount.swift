import Foundation
import SwiftData

enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

@Model
final class OTPAccount {
    var id: UUID = UUID()
    var issuer: String = ""
    var accountName: String = ""
    var algorithm: OTPAlgorithm = OTPAlgorithm.sha1
    var digits: Int = 6
    var period: Int = 30
    var createdAt: Date = Date.now

    var keychainKey: String {
        "kagimori.otp.\(id.uuidString)"
    }

    init(
        issuer: String,
        accountName: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30
    ) {
        self.id = UUID()
        self.issuer = issuer
        self.accountName = accountName
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.createdAt = .now
    }
}
