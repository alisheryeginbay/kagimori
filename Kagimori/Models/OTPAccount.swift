import Foundation
import SwiftData

enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

@Model
final class OTPAccount {
    var id: UUID
    var issuer: String
    var accountName: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var createdAt: Date

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
