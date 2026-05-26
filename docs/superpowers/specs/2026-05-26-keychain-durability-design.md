# Keychain Durability & Safe Recovery — Design Spec

**Date:** 2026-05-26
**Status:** Approved for planning
**Goal in one line:** A TOTP secret, once added, can never be silently lost — not by a bug, not by a failed save, not by dev/prod cross-contamination, and ideally not even by losing the phone.

## Background: what broke

Some codes display `--- ---`. Investigation (confirmed on-device with a temporary diagnostic) found:

- The `--- ---` placeholder renders from two guard-failure paths: secret missing from Keychain (`CodeCardView.swift:9-10`) or secret present-but-undecodable (`TOTPGenerator.swift:12-13`). The affected accounts are all the **missing** case (`keychain: absent`, `errSecItemNotFound`), not the decode case.
- The user has **no other device**, and the affected accounts were added on this phone and previously worked. So the secrets were present and then destroyed locally.
- Root cause: commit `6db3dd8` ("add iCloud sync support") introduced a startup migration (`KagimoriApp.swift:21-25`) that runs on **every launch for every account** and calls `KeychainService.save`, which performs a **non-atomic `delete`-then-`SecItemAdd`** (`KeychainService.swift:10,21`) with the result discarded. When the `add` fails after the `delete` succeeds (lock race, `errSecDuplicateItem` from iCloud-Keychain timing, or watchdog kill mid-loop), the secret is permanently destroyed. Per-account in a loop → only *some* die.

### How the data is stored (mental model)

Each account is split into two halves, in two stores, linked by `keychainKey` (derived from `OTPAccount.id`):

| Half | Store | Synced by | Configured at |
|------|-------|-----------|---------------|
| Metadata (issuer, name, digits, period, id) | SwiftData | **CloudKit** | `cloudKitDatabase: .automatic` (`KagimoriApp.swift:12`) |
| Secret (the seed) | Keychain | **iCloud Keychain** | `kSecAttrSynchronizable: true` (`KeychainService.swift:18`) |

CloudKit and iCloud Keychain are independent systems (different servers, timing, and Settings toggles). When metadata arrives but the secret hasn't, the card shows `--- ---`. This split is *not* the cause of data loss, but it is the cause of the cosmetic missing-secret state.

### The dev/prod asymmetry

Two build configs ship as two apps: `com.kagimori.app` (Release/prod) and `com.kagimori.app.debug` (Debug/dev).

- **Metadata is shared**: `Kagimori.entitlements` hardcodes one CloudKit container, `iCloud.com.kagimori.app`, and both configs use that one entitlements file. Both apps read/write the same metadata bucket.
- **Secrets are siloed**: iOS scopes Keychain items to the app's bundle ID (the default keychain access group). Different bundle IDs → separate vaults.

Consequence: dev shares prod's metadata bucket but not its secrets. Because the bucket is a two-way street, **dev actively endangers prod**: testing import in dev writes metadata into the shared bucket (→ appears in prod as `--- ---`, since the secret lands in dev's vault), and deleting test accounts in dev propagates the deletion to prod. Since the transfer/import feature is developed in dev, this is a live contamination/deletion risk for real prod data.

## Goals

1. No code path may delete or overwrite-destroy a secret as a side effect of saving one.
2. App launch performs **zero** destructive Keychain operations.
3. Creating an account is all-or-nothing: a metadata row never exists without its secret.
4. Re-importing the user's full backup produces **zero duplicates** and **restores missing secrets in place** (the recovery path).
5. The dev build is fully isolated from prod: nothing done in dev can alter prod's data.
6. A user-controlled backup (export) exists as a belt-and-suspenders safety net.

## Non-goals (explicitly out of scope)

- Distinguishing "missing" vs "bad" secret as separate UI states on the card (cosmetic; both stay `--- ---` for now).
- Cleaning up legacy non-synchronizable Keychain items from pre-sync installs (this user has none; see note in §1).
- Changing the storage model away from Keychain + iCloud Keychain. We keep iCloud Keychain sync — it is the *automatic backup* that protects against phone loss.

## Design

Six pillars. Pillars 1–4 prevent loss; 5–6 enable recovery and ongoing safety.

### 1. Non-destructive `KeychainService.save`

Replace delete-then-add with add-or-update. Never delete on the save path.

- `SecItemAdd` with `kSecAttrSynchronizable: true`, `kSecAttrAccessibleWhenUnlocked`.
- If it returns `errSecDuplicateItem`, the synchronizable item already exists → `SecItemUpdate` its `kSecValueData` in place (match by service + account + `synchronizable: true`).
- Any other non-success status → return `false` **without having modified anything**.

A failed write therefore leaves the existing secret intact. `save` returns `true` only on a confirmed write.

Remove `migrateToSyncable` (no longer called — see Pillar 2).

> Note on legacy items: changing an item's `synchronizable` attribute in place is not supported by `SecItemUpdate` (it is part of the primary key) — that is precisely why the old code used the destructive delete-then-add. We are not migrating legacy non-synchronizable items because this user has none. If ever needed, the safe pattern is verify-before-delete: write and confirm the new syncable copy, *then* delete the old one — never delete first.

### 2. Remove the every-launch migration

Delete the account-iteration migration block in `KagimoriApp.init()` (`KagimoriApp.swift:21-25`) entirely. Items are already syncable; the loop is now pointless and was the source of the loss. `init()` keeps only the `ModelContainer` setup.

### 3. Account creation is all-or-nothing

The three create flows currently save the secret, ignore the result, then insert the metadata regardless:

- `AddAccountView.swift:54-55`
- `ManualEntryView.swift:80-81`
- `TransferView.swift:76-77`

Change each to: only `modelContext.insert(account)` **after** `KeychainService.save(...)` returns `true`. On failure, surface an error to the user (alert for the single-add flows; per-row failure count for import) and do **not** insert the metadata row. No more silent `--- ---` ghosts at creation time.

### 4. Isolate dev from prod (separate CloudKit container)

Give the Debug config its own CloudKit container so dev cannot read or write prod's metadata bucket. Dev already has its own Keychain vault automatically, so this single change fully isolates dev.

- Add `Kagimori/Kagimori.debug.entitlements` identical to the prod entitlements but with the container/ubiquity identifiers set to `iCloud.com.kagimori.app.debug`.
- In `project.yml`, override `CODE_SIGN_ENTITLEMENTS` under `configs.Debug` to point at the debug entitlements; Release continues to use `Kagimori/Kagimori.entitlements`.
- Run `xcodegen generate`. Automatic signing (team `84QSJK68P2`) registers the new container.
- No app code change needed: `cloudKitDatabase: .automatic` reads the container from the active build's entitlements.

**Safety:** prod stays on `iCloud.com.kagimori.app` untouched. Dev starts with an empty bucket of its own. Recommend deleting and reinstalling the dev app after this change so its local store starts clean (dev is disposable).

### 5. Idempotent import (the recovery path)

Make `TwoFASImporter` + the import loop in `TransferView` recognize what already exists, so re-importing the full backup heals rather than duplicates. For each parsed entry:

1. **Match by secret** against existing accounts (compare the parsed secret to each existing account's retrieved secret). If an existing account already has this secret → **skip** (it is already present and working). This is the duplicate-prevention key, since the secret is the true identity of a credential.
2. Else **match by issuer + account name** (case-insensitive, trimmed) against existing accounts that are **missing** their secret. If found → **restore**: `save` the secret to that existing account's `keychainKey`. No new row is created; the red account turns green in place.
3. Else → **new**: create the account (Pillar 3 rules apply — insert only if the secret saved).

Report a summary: `restored N, skipped N, added N, failed N`.

Edge cases: multiple existing secret-less rows with the same issuer+name → match the first (rare for TOTP). A parsed secret that matches no existing secret and whose name matches a green account is treated as new (different credential).

### 6. Export (belt-and-suspenders backup)

Wire the existing `TwoFASExporter` into the UI (a button in `TransferView`/Settings, alongside Import), producing a 2FAS-format backup file via the share sheet. Export reads secrets (read-only — safe) for the current accounts and never mutates state.

## Error handling

- `KeychainService.save` returns a `Bool`; callers must honor it (Pillar 3). No `@discardableResult` on the save path going forward.
- Single-add flows show a user-facing alert on save failure.
- Import shows a summary including any failures; failed rows are not inserted.

## Testing & verification

There is no test target today. Plan:

- **Pure-logic unit tests (recommended, new lightweight test target):** Base32 decode round-trip; TwoFAS import dedup/upsert matching (skip-by-secret, restore-by-name, add-new); TwoFAS export→import round-trip equivalence. These cover the riskiest new logic (import dedup).
- **Manual on-device verification:** keep the temporary Diagnostics screen until recovery is confirmed. Verify: launch performs no deletions (codes survive repeated launches); a forced save failure does not create a ghost row; re-import yields `restored/skipped` counts with no duplicates; dev shows its own empty world.

## Recovery sequence (operational, after implementation)

1. Build & install the fixed **prod** app.
2. **Export** current working accounts as a safety-net file.
3. **Re-import** the full 2FAS backup → restores the red accounts in place, skips the greens, no duplicates.
4. Confirm **all-green** in Diagnostics.
5. Remove the temporary diagnostic code (`KeychainService.diagnose`, `KeychainDiagnosis`, `DiagnosticsView`, the Settings link) in a separate cleanup commit.

## Success criteria

- Grep confirms no `delete`-before-add and no `delete` on any save/migration path.
- App launch performs zero destructive Keychain operations.
- Adding an account with a forced save failure produces no metadata row.
- Re-importing the backup restores all missing secrets with zero duplicate rows.
- Dev build uses `iCloud.com.kagimori.app.debug`; account changes in dev do not appear in prod.

## Affected files

- `Kagimori/Services/KeychainService.swift` — non-destructive `save`; remove `migrateToSyncable`.
- `Kagimori/KagimoriApp.swift` — remove migration loop.
- `Kagimori/Views/AddAccountView.swift`, `Kagimori/Views/ManualEntryView.swift` — gate insert on save success + error alert.
- `Kagimori/Views/TransferView.swift` — gate insert on save success; idempotent import; export button.
- `Kagimori/Services/TwoFASImporter.swift` — support dedup/upsert matching (or expose data the view needs).
- `Kagimori/Kagimori.debug.entitlements` (new) + `project.yml` — dev CloudKit container isolation.
- Temporary, removed post-recovery: `KeychainService.diagnose` / `KeychainDiagnosis` / `DiagnosticsView` / Settings link.
