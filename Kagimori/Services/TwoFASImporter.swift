import Foundation

enum TwoFASImporter {
    struct Backup: Decodable {
        let services: [Service]
    }

    struct Service: Decodable {
        let name: String
        let secret: String
        let otp: OTP
    }

    struct OTP: Decodable {
        let account: String?
        let issuer: String?
        let tokenType: String?
        let algorithm: String?
        let digits: Int?
        let period: Int?
    }

    static func parse(data: Data) throws -> [OTPAuthURI.ParsedAccount] {
        let backup = try JSONDecoder().decode(Backup.self, from: data)

        return backup.services.compactMap { service in
            let tokenType = service.otp.tokenType?.uppercased() ?? "TOTP"
            guard tokenType == "TOTP" else { return nil }

            let secret = service.secret
                .filter { !$0.isWhitespace }
                .replacingOccurrences(of: "=", with: "")
                .uppercased()
            guard !secret.isEmpty else { return nil }

            let algorithm: OTPAlgorithm
            switch service.otp.algorithm?.uppercased() {
            case "SHA256": algorithm = .sha256
            case "SHA512": algorithm = .sha512
            default: algorithm = .sha1
            }

            return OTPAuthURI.ParsedAccount(
                issuer: service.otp.issuer ?? service.name,
                accountName: service.otp.account ?? "",
                secret: secret,
                algorithm: algorithm,
                digits: service.otp.digits ?? 6,
                period: service.otp.period ?? 30
            )
        }
    }
}
