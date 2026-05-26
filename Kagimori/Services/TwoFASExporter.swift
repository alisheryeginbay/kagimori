import Foundation

enum TwoFASExporter {
    /// Default 2FAS icon collection identifier used for label-based icons.
    private static let defaultIconCollectionID = "a5b3fb65-4ec5-43e6-8ec1-49e24ca9e7ad"

    struct ExportAccount {
        let issuer: String
        let accountName: String
        let secret: String
        let algorithm: OTPAlgorithm
        let digits: Int
        let period: Int
    }

    private struct Backup: Encodable {
        let services: [Service]
        let groups: [String]
        let updatedAt: Int
        let schemaVersion: Int
        let appVersionCode: Int
        let appVersionName: String
        let appOrigin: String
    }

    private struct Service: Encodable {
        let name: String
        let secret: String
        let updatedAt: Int
        let otp: OTP
        let order: Order
        let icon: Icon
    }

    private struct OTP: Encodable {
        let account: String
        let issuer: String
        let digits: Int
        let period: Int
        let algorithm: String
        let tokenType: String
        let source: String
    }

    private struct Order: Encodable {
        let position: Int
    }

    private struct Icon: Encodable {
        let selected: String
        let label: IconLabel
        let iconCollection: IconCollection
    }

    private struct IconLabel: Encodable {
        let text: String
        let backgroundColor: String
    }

    private struct IconCollection: Encodable {
        let id: String
    }

    static func makeBackup(from accounts: [ExportAccount]) throws -> Data {
        let now = Int(Date.now.timeIntervalSince1970 * 1000)

        let services = accounts.enumerated().map { index, account -> Service in
            let name = account.issuer.isEmpty ? account.accountName : account.issuer
            return Service(
                name: name,
                secret: account.secret,
                updatedAt: now,
                otp: OTP(
                    account: account.accountName,
                    issuer: account.issuer,
                    digits: account.digits,
                    period: account.period,
                    algorithm: account.algorithm.rawValue,
                    tokenType: "TOTP",
                    source: "Manual"
                ),
                order: Order(position: index),
                icon: Icon(
                    selected: "Label",
                    label: IconLabel(
                        text: labelText(for: name),
                        backgroundColor: "Orange"
                    ),
                    iconCollection: IconCollection(id: defaultIconCollectionID)
                )
            )
        }

        let backup = Backup(
            services: services,
            groups: [],
            updatedAt: now,
            schemaVersion: 4,
            appVersionCode: 5000000,
            appVersionName: "5.0.0",
            appOrigin: "ios"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    private static func labelText(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "??" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
