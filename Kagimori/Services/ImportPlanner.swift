import Foundation

/// Pure decision logic for idempotent imports. Decides, for one incoming entry,
/// whether it is already present (skip), matches a secret-less row to heal
/// (restore), or is brand-new (add). No side effects, no Keychain access.
enum ImportPlanner {
    /// Snapshot of an existing account. `secret` is nil when the account's
    /// secret is missing from the Keychain (a broken "--- ---" row).
    struct ExistingAccount: Equatable {
        let keychainKey: String
        let issuer: String
        let accountName: String
        let secret: String?
    }

    enum Action: Equatable {
        case skip                          // already present — secret already stored
        case restore(keychainKey: String)  // fill a secret-less row in place
        case add                           // brand-new account
    }

    static func action(
        forSecret secret: String,
        issuer: String,
        accountName: String,
        existing: [ExistingAccount]
    ) -> Action {
        let normalizedSecret = secret.uppercased()
        if existing.contains(where: { $0.secret?.uppercased() == normalizedSecret }) {
            return .skip
        }

        let issuerKey = issuer.trimmingCharacters(in: .whitespaces).lowercased()
        let nameKey = accountName.trimmingCharacters(in: .whitespaces).lowercased()
        if let match = existing.first(where: {
            $0.secret == nil
                && $0.issuer.trimmingCharacters(in: .whitespaces).lowercased() == issuerKey
                && $0.accountName.trimmingCharacters(in: .whitespaces).lowercased() == nameKey
        }) {
            return .restore(keychainKey: match.keychainKey)
        }

        return .add
    }
}
