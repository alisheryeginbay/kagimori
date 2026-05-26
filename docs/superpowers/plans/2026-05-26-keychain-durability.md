# Keychain Durability & Safe Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TOTP secret storage impossible to silently lose, isolate the dev build from prod, and provide an idempotent re-import recovery path plus a manual export backup.

**Architecture:** Secrets stay in the Keychain (synchronizable via iCloud Keychain — the automatic backup); metadata stays in SwiftData/CloudKit. The fix removes every destructive Keychain operation: `save` becomes add-or-update (never delete-first), the every-launch migration is deleted, and account creation only persists metadata after the secret is confirmed saved. Recovery is a pure, unit-tested import planner that skips duplicates and restores secret-less rows in place. Dev gets its own CloudKit container so it can never touch prod.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Security framework (Keychain), XcodeGen, XCTest.

**Design spec:** `docs/superpowers/specs/2026-05-26-keychain-durability-design.md`

**Shared commands** (used throughout):
- Build: `xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: `xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
- Regenerate project after editing `project.yml` or adding files: `xcodegen generate`

> **Note on the temporary diagnostic code:** `KeychainService.diagnose`, `KeychainDiagnosis`, and the Settings → Diagnostics screen are currently uncommitted on this branch. They stay until on-device recovery is verified, then Task 10 removes them.

> **Note on export encryption:** The spec mentions an "encrypted backup file." The 2FAS format this app imports is unencrypted JSON, so the export in Task 8 produces an **unencrypted** 2FAS-compatible file (symmetrical with import). Password-encrypted export is a future enhancement, not in this plan. The file contains plaintext secrets — the UI warns the user to store it safely.

---

## File Structure

- `Kagimori/Services/KeychainService.swift` — `save` becomes non-destructive; `migrateToSyncable` removed; `@discardableResult` removed from `save`.
- `Kagimori/KagimoriApp.swift` — every-launch migration loop removed.
- `Kagimori/Views/AddAccountView.swift`, `Kagimori/Views/ManualEntryView.swift` — gate insert on save success + error alert.
- `Kagimori/Services/ImportPlanner.swift` (new) — pure import decision logic (skip/restore/add).
- `Kagimori/Views/TransferView.swift` — idempotent import via `ImportPlanner`; export button.
- `Kagimori/Views/ShareSheet.swift` (new) — `UIActivityViewController` wrapper for sharing the export file.
- `Kagimori/Kagimori.debug.entitlements` (new) + `project.yml` — dev CloudKit container isolation.
- `KagimoriTests/` (new) — `Base32Tests.swift`, `ImportPlannerTests.swift`, `TwoFASRoundTripTests.swift`.

---

## Task 1: Make `KeychainService.save` non-destructive

**Files:**
- Modify: `Kagimori/Services/KeychainService.swift:7-22`

- [ ] **Step 1: Replace the `save` function body with add-or-update**

Replace lines 7-22 (the current `@discardableResult static func save(...)`) with:

```swift
    @discardableResult
    static func save(secret: String, for key: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }

        // Try to add a new synchronizable item. Never delete first.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecDuplicateItem else { return false }

        // A synchronizable item already exists — update its value in place.
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
```

(Keep `@discardableResult` for now; it is removed in Task 7 once every call site honors the result.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Kagimori/Services/KeychainService.swift
git commit -m "fix: make KeychainService.save non-destructive (add-or-update, never delete-first)"
```

---

## Task 2: Remove the every-launch destructive migration

This is the change that stops the data loss. After this task the app is safe to install.

**Files:**
- Modify: `Kagimori/KagimoriApp.swift:8-26`
- Modify: `Kagimori/Services/KeychainService.swift:53-57`

- [ ] **Step 1: Remove the migration loop from `KagimoriApp.init()`**

Replace the `init()` (lines 8-26) with:

```swift
    init() {
        let schema = Schema([OTPAccount.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to configure SwiftData: \(error)")
        }
    }
```

- [ ] **Step 2: Remove `migrateToSyncable` from `KeychainService`**

Delete this block (lines 53-57):

```swift
    @discardableResult
    static func migrateToSyncable(for key: String) -> Bool {
        guard let secret = retrieve(for: key) else { return false }
        return save(secret: secret, for: key)
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **` (no reference to `migrateToSyncable` remains)

- [ ] **Step 4: Commit**

```bash
git add Kagimori/KagimoriApp.swift Kagimori/Services/KeychainService.swift
git commit -m "fix: remove destructive every-launch keychain migration"
```

---

## Task 3: Account creation is all-or-nothing (single-add flows)

**Files:**
- Modify: `Kagimori/Views/AddAccountView.swift:46-57`
- Modify: `Kagimori/Views/AddAccountView.swift:14-44` (add alert + state)
- Modify: `Kagimori/Views/ManualEntryView.swift:68-83`
- Modify: `Kagimori/Views/ManualEntryView.swift:4-22` (add alert + state)

- [ ] **Step 1: Add error state + alert to `AddAccountView`**

Add these two `@State` properties after line 7 (`@State private var mode: EntryMode = .scan`):

```swift
    @State private var showError = false
    @State private var errorMessage = ""
```

Add this alert modifier to the `VStack` — place it immediately after the `.toolbar { ... }` block (after line 42, before the closing brace of the `NavigationStack` body):

```swift
            .alert("Add Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
```

- [ ] **Step 2: Gate `AddAccountView.saveAccount` on save success**

Replace `saveAccount` (lines 46-57) with:

```swift
    private func saveAccount(_ parsed: OTPAuthURI.ParsedAccount) {
        let account = OTPAccount(
            issuer: parsed.issuer,
            accountName: parsed.accountName,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period
        )
        guard KeychainService.save(secret: parsed.secret, for: account.keychainKey) else {
            errorMessage = "Couldn't save the secret securely. The account was not added."
            showError = true
            return
        }
        modelContext.insert(account)
        dismiss()
    }
```

- [ ] **Step 3: Add error state + alert to `ManualEntryView`**

Add these two `@State` properties after line 14 (`@State private var showAdvanced = false`):

```swift
    @State private var showError = false
    @State private var errorMessage = ""
```

Add this alert modifier to the `Form` — place it immediately after the closing brace of the `Form { ... }` body (after line 65):

```swift
        .alert("Add Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
```

- [ ] **Step 4: Gate `ManualEntryView.addAccount` on save success**

Replace `addAccount` (lines 68-83) with:

```swift
    private func addAccount() {
        let cleanSecret = secret
            .filter { !$0.isWhitespace }
            .uppercased()

        let account = OTPAccount(
            issuer: issuer,
            accountName: accountName,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
        guard KeychainService.save(secret: cleanSecret, for: account.keychainKey) else {
            errorMessage = "Couldn't save the secret securely. The account was not added."
            showError = true
            return
        }
        modelContext.insert(account)
        dismiss()
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Kagimori/Views/AddAccountView.swift Kagimori/Views/ManualEntryView.swift
git commit -m "fix: only create an account after its secret is confirmed saved"
```

---

## Task 4: Add a unit-test target

**Files:**
- Modify: `project.yml:13-41`
- Create: `KagimoriTests/Base32Tests.swift`

- [ ] **Step 1: Add the test target and scheme to `project.yml`**

Add a `scheme` block to the `Kagimori` target (insert immediately after its `settings:` block ends — i.e. after line 41) and add a new `KagimoriTests` target. The `targets:` section should read:

```yaml
targets:
  Kagimori:
    type: application
    platform: iOS
    sources:
      - Kagimori
      - path: Kagimori.icon
        type: folder
    settings:
      base:
        DEVELOPMENT_TEAM: 84QSJK68P2
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: com.kagimori.app
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: 1
        GENERATE_INFOPLIST_FILE: true
        INFOPLIST_FILE: Kagimori/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: Kagimori
        INFOPLIST_KEY_CFBundleDisplayName: Kagimori
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        INFOPLIST_KEY_UILaunchScreen_Generation: true
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
        CODE_SIGN_ENTITLEMENTS: Kagimori/Kagimori.entitlements
      configs:
        Debug:
          PRODUCT_BUNDLE_IDENTIFIER: com.kagimori.app.debug
          INFOPLIST_KEY_CFBundleDisplayName: "Kagimori Dev"
    scheme:
      testTargets:
        - KagimoriTests

  KagimoriTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - KagimoriTests
    dependencies:
      - target: Kagimori
    settings:
      base:
        GENERATE_INFOPLIST_FILE: true
        PRODUCT_BUNDLE_IDENTIFIER: com.kagimori.app.tests
        DEVELOPMENT_TEAM: 84QSJK68P2
        CODE_SIGN_STYLE: Automatic
```

- [ ] **Step 2: Create the first test (Base32 characterization)**

Create `KagimoriTests/Base32Tests.swift`:

```swift
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
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: `Created project at Kagimori.xcodeproj` (the `postGenCommand` sed also runs)

- [ ] **Step 4: Run the test suite to verify the target works and tests pass**

Run: `xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `** TEST SUCCEEDED **` with `Base32Tests` passing 3 tests

- [ ] **Step 5: Commit**

```bash
git add project.yml KagimoriTests/Base32Tests.swift Kagimori.xcodeproj/project.pbxproj
git commit -m "test: add KagimoriTests target with Base32 characterization tests"
```

---

## Task 5: Pure import-decision logic (`ImportPlanner`) — TDD

**Files:**
- Create: `Kagimori/Services/ImportPlanner.swift`
- Test: `KagimoriTests/ImportPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `KagimoriTests/ImportPlannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Regenerate (to include the new test file) and run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KagimoriTests/ImportPlannerTests`
Expected: FAIL — compile error "cannot find 'ImportPlanner' in scope"

- [ ] **Step 3: Implement `ImportPlanner`**

Create `Kagimori/Services/ImportPlanner.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate the project (new source file) and run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KagimoriTests/ImportPlannerTests`
Expected: `** TEST SUCCEEDED **` — 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add Kagimori/Services/ImportPlanner.swift KagimoriTests/ImportPlannerTests.swift Kagimori.xcodeproj/project.pbxproj
git commit -m "feat: add pure ImportPlanner decision logic with tests"
```

---

## Task 6: TwoFAS export→import round-trip — TDD

Locks in that the exporter and importer agree, since both Task 7 (import) and Task 8 (export) depend on it.

**Files:**
- Test: `KagimoriTests/TwoFASRoundTripTests.swift`

- [ ] **Step 1: Write the failing test**

Create `KagimoriTests/TwoFASRoundTripTests.swift`:

```swift
import XCTest
@testable import Kagimori

final class TwoFASRoundTripTests: XCTestCase {
    func testExportThenImportPreservesAccounts() throws {
        let accounts = [
            TwoFASExporter.ExportAccount(
                issuer: "npm", accountName: "me@x.com", secret: "JBSWY3DP",
                algorithm: .sha1, digits: 6, period: 30
            ),
            TwoFASExporter.ExportAccount(
                issuer: "GitHub", accountName: "octocat", secret: "MZXW6YTBOI",
                algorithm: .sha256, digits: 8, period: 60
            ),
        ]

        let data = try TwoFASExporter.makeBackup(from: accounts)
        let parsed = try TwoFASImporter.parse(data: data)

        XCTAssertEqual(parsed.count, 2)

        let npm = try XCTUnwrap(parsed.first { $0.issuer == "npm" })
        XCTAssertEqual(npm.accountName, "me@x.com")
        XCTAssertEqual(npm.secret, "JBSWY3DP")
        XCTAssertEqual(npm.algorithm, .sha1)
        XCTAssertEqual(npm.digits, 6)
        XCTAssertEqual(npm.period, 30)

        let gh = try XCTUnwrap(parsed.first { $0.issuer == "GitHub" })
        XCTAssertEqual(gh.accountName, "octocat")
        XCTAssertEqual(gh.secret, "MZXW6YTBOI")
        XCTAssertEqual(gh.algorithm, .sha256)
        XCTAssertEqual(gh.digits, 8)
        XCTAssertEqual(gh.period, 60)
    }
}
```

- [ ] **Step 2: Regenerate the project (new test file) and run the test**

Run: `xcodegen generate && xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KagimoriTests/TwoFASRoundTripTests`
Expected: `** TEST SUCCEEDED **`. (If it fails, the exporter/importer disagree — fix the mismatch in `TwoFASExporter`/`TwoFASImporter` before continuing; do not change the test to match a bug.)

- [ ] **Step 3: Commit**

```bash
git add KagimoriTests/TwoFASRoundTripTests.swift Kagimori.xcodeproj/project.pbxproj
git commit -m "test: add TwoFAS export/import round-trip test"
```

---

## Task 7: Idempotent import + enforce save result (`TransferView`)

**Files:**
- Modify: `Kagimori/Views/TransferView.swift:52-89` (rewrite `importFile`)
- Modify: `Kagimori/Services/KeychainService.swift:7` (remove `@discardableResult` from `save`)

- [ ] **Step 1: Rewrite `importFile` to use `ImportPlanner`**

Replace `importFile` (lines 52-89) with:

```swift
    private func importFile(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importAlert = ImportAlert(title: "Import Failed", message: "Unable to access the selected file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let parsed = try TwoFASImporter.parse(data: data)
                guard !parsed.isEmpty else {
                    importAlert = ImportAlert(title: "No Accounts Found", message: "The file contained no TOTP accounts to import.")
                    return
                }

                let existingAccounts = (try? modelContext.fetch(FetchDescriptor<OTPAccount>())) ?? []
                let snapshot = existingAccounts.map { account in
                    ImportPlanner.ExistingAccount(
                        keychainKey: account.keychainKey,
                        issuer: account.issuer,
                        accountName: account.accountName,
                        secret: KeychainService.retrieve(for: account.keychainKey)
                    )
                }

                var added = 0, restored = 0, skipped = 0, failed = 0
                for entry in parsed {
                    switch ImportPlanner.action(
                        forSecret: entry.secret,
                        issuer: entry.issuer,
                        accountName: entry.accountName,
                        existing: snapshot
                    ) {
                    case .skip:
                        skipped += 1
                    case .restore(let keychainKey):
                        if KeychainService.save(secret: entry.secret, for: keychainKey) {
                            restored += 1
                        } else {
                            failed += 1
                        }
                    case .add:
                        let otp = OTPAccount(
                            issuer: entry.issuer,
                            accountName: entry.accountName,
                            algorithm: entry.algorithm,
                            digits: entry.digits,
                            period: entry.period
                        )
                        if KeychainService.save(secret: entry.secret, for: otp.keychainKey) {
                            modelContext.insert(otp)
                            added += 1
                        } else {
                            failed += 1
                        }
                    }
                }

                var lines = ["Added \(added)", "restored \(restored)", "skipped \(skipped)"]
                if failed > 0 { lines.append("failed \(failed)") }
                importAlert = ImportAlert(title: "Import Complete", message: lines.joined(separator: ", ") + ".")
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }
```

- [ ] **Step 2: Remove `@discardableResult` from `KeychainService.save`**

In `Kagimori/Services/KeychainService.swift`, delete the line `@discardableResult` immediately above `static func save(secret: String, for key: String) -> Bool {` (it is now line 7). Leave the `@discardableResult` on `delete` untouched.

- [ ] **Step 3: Build to verify it compiles (no unused-result warnings)**

Run: `xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **` with no "result of call to 'save' is unused" warnings (all three call sites — `AddAccountView`, `ManualEntryView`, `TransferView` — now check the result).

- [ ] **Step 4: Run the full test suite (nothing regressed)**

Run: `xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Kagimori/Views/TransferView.swift Kagimori/Services/KeychainService.swift
git commit -m "feat: idempotent 2FAS import (skip/restore/add) and enforce save result"
```

---

## Task 8: Export backup file (`TransferView` + `ShareSheet`)

**Files:**
- Create: `Kagimori/Views/ShareSheet.swift`
- Modify: `Kagimori/Views/TransferView.swift` (add export section, state, sheet, and `exportBackup`)

- [ ] **Step 1: Create the share-sheet wrapper**

Create `Kagimori/Views/ShareSheet.swift`:

```swift
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 2: Add export state + an `ExportItem` to `TransferView`**

In `Kagimori/Views/TransferView.swift`, add after `@State private var importAlert: ImportAlert?` (line 8):

```swift
    @State private var exportItem: ExportItem?
```

And add this struct next to the existing `ImportAlert` struct (after the `ImportAlert` definition, around line 14):

```swift
    private struct ExportItem: Identifiable {
        let id = UUID()
        let url: URL
    }
```

- [ ] **Step 3: Add the Export section to the List**

In `body`, add a second `Section` **inside** the `List` — immediately after the "Import from" `Section` (after its `footer` block closes on line 34) and before the `List`'s closing brace on line 35:

```swift
            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves a 2FAS-format file containing your secrets. The file is unencrypted — store it somewhere safe.")
            }
```

- [ ] **Step 4: Add the share sheet presentation**

Add this modifier right after the existing `.alert(item: $importAlert) { ... }` block (around line 49):

```swift
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
```

- [ ] **Step 5: Add the `exportBackup` function**

Add this method to `TransferView` (after `importFile`):

```swift
    private func exportBackup() {
        let accounts = (try? modelContext.fetch(FetchDescriptor<OTPAccount>())) ?? []
        let exportAccounts = accounts.compactMap { account -> TwoFASExporter.ExportAccount? in
            guard let secret = KeychainService.retrieve(for: account.keychainKey) else { return nil }
            return TwoFASExporter.ExportAccount(
                issuer: account.issuer,
                accountName: account.accountName,
                secret: secret,
                algorithm: account.algorithm,
                digits: account.digits,
                period: account.period
            )
        }
        guard !exportAccounts.isEmpty else {
            importAlert = ImportAlert(title: "Nothing to Export", message: "No accounts with a stored secret were found.")
            return
        }
        do {
            let data = try TwoFASExporter.makeBackup(from: exportAccounts)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("kagimori-backup.2fas")
            try data.write(to: url, options: .atomic)
            exportItem = ExportItem(url: url)
        } catch {
            importAlert = ImportAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
```

- [ ] **Step 6: Regenerate the project (new source file) and build**

Run: `xcodegen generate && xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Kagimori/Views/ShareSheet.swift Kagimori/Views/TransferView.swift Kagimori.xcodeproj/project.pbxproj
git commit -m "feat: export accounts to a 2FAS-format backup file"
```

---

## Task 9: Isolate the dev build's CloudKit container

**Files:**
- Create: `Kagimori/Kagimori.debug.entitlements`
- Modify: `project.yml` (`configs.Debug`)

- [ ] **Step 1: Create the debug entitlements file**

Create `Kagimori/Kagimori.debug.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.kagimori.app.debug</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudDocuments</string>
		<string>CloudKit</string>
	</array>
	<key>com.apple.developer.ubiquity-container-identifiers</key>
	<array>
		<string>iCloud.com.kagimori.app.debug</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Point the Debug config at the debug entitlements**

In `project.yml`, update the `configs.Debug` block of the `Kagimori` target to add the entitlements override:

```yaml
      configs:
        Debug:
          PRODUCT_BUNDLE_IDENTIFIER: com.kagimori.app.debug
          INFOPLIST_KEY_CFBundleDisplayName: "Kagimori Dev"
          CODE_SIGN_ENTITLEMENTS: Kagimori/Kagimori.debug.entitlements
```

(The target-level `CODE_SIGN_ENTITLEMENTS: Kagimori/Kagimori.entitlements` remains and is used by the Release config.)

- [ ] **Step 3: Regenerate and build the Debug configuration**

Run: `xcodegen generate && xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`. (Simulator builds sign locally and don't register the container with Apple; full registration of `iCloud.com.kagimori.app.debug` happens on the first device install via `make dev`, which automatic signing handles.)

- [ ] **Step 4: Commit**

```bash
git add Kagimori/Kagimori.debug.entitlements project.yml Kagimori.xcodeproj/project.pbxproj
git commit -m "fix: give dev build its own CloudKit container to isolate it from prod"
```

- [ ] **Step 5: (Manual, on device) Verify isolation**

After `make dev`, delete and reinstall the dev app so its local store starts clean. Add a test account in dev; confirm it does **not** appear in the prod app. (No automated test — this is verified on device.)

---

## Task 10: Remove temporary diagnostics — DO THIS LAST, AFTER ON-DEVICE RECOVERY

Do not run this task until the recovery sequence in the spec is complete and Diagnostics shows all-green on the device.

**Files:**
- Modify: `Kagimori/Services/KeychainService.swift` (remove diagnostics)
- Modify: `Kagimori/Views/SettingsView.swift` (remove Diagnostics screen)

- [ ] **Step 1: Remove diagnostics from `KeychainService.swift`**

Delete everything from the `// MARK: - Diagnostics (temporary)` comment through the end of the file — i.e. the `diagnose` function, the `existsStatus` helper, the closing of the enum's diagnostics region, and the entire `KeychainDiagnosis` struct. The file should end with the `delete` function and the enum's closing brace:

```swift
    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

- [ ] **Step 2: Remove the Diagnostics screen from `SettingsView.swift`**

Restore `SettingsView.swift` to contain only the settings list (remove the `import SwiftData`, the "Diagnostics" `Section`, and the `DiagnosticsView` + `DiagnosticRow` structs). The full file should read:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    NavigationLink {
                        TransferView()
                    } label: {
                        Label("Transfer Accounts", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

- [ ] **Step 3: Build and test**

Run: `xcodebuild test -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Kagimori/Services/KeychainService.swift Kagimori/Views/SettingsView.swift
git commit -m "chore: remove temporary keychain diagnostics"
```

---

## Definition of done

- [ ] No code path deletes a secret as a side effect of saving (`save` is add-or-update; `delete` only on intentional account removal).
- [ ] App launch performs zero destructive Keychain operations (migration removed).
- [ ] All three add flows insert metadata only after a confirmed secret save.
- [ ] `ImportPlanner` tests + Base32 tests + round-trip test all pass.
- [ ] Re-importing the backup on device restores red rows in place with zero duplicates (verified via the import summary and Diagnostics).
- [ ] Dev build uses `iCloud.com.kagimori.app.debug`; dev account changes do not appear in prod.
- [ ] Temporary diagnostics removed (Task 10, after recovery).
