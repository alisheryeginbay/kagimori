import Foundation

enum OTPAuthURI {
    struct ParsedAccount {
        let issuer: String
        let accountName: String
        let secret: String
        let algorithm: OTPAlgorithm
        let digits: Int
        let period: Int
    }

    static func parse(_ uriString: String) -> ParsedAccount? {
        guard let url = URL(string: uriString),
              url.scheme == "otpauth",
              url.host(percentEncoded: false) == "totp"
        else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let label = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = label.split(separator: ":", maxSplits: 1)

        let labelIssuer: String?
        let accountName: String
        if parts.count == 2 {
            labelIssuer = String(parts[0])
            accountName = String(parts[1])
        } else {
            labelIssuer = nil
            accountName = label
        }

        guard let secret = queryItems.first(where: { $0.name == "secret" })?.value else {
            return nil
        }

        let issuer = queryItems.first(where: { $0.name == "issuer" })?.value ?? labelIssuer ?? ""
        let algorithmStr = queryItems.first(where: { $0.name == "algorithm" })?.value?.uppercased() ?? "SHA1"
        let digits = Int(queryItems.first(where: { $0.name == "digits" })?.value ?? "6") ?? 6
        let period = Int(queryItems.first(where: { $0.name == "period" })?.value ?? "30") ?? 30

        let algorithm: OTPAlgorithm
        switch algorithmStr {
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: algorithm = .sha1
        }

        return ParsedAccount(
            issuer: issuer,
            accountName: accountName,
            secret: secret.uppercased(),
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}
