# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

Kagimori is an iOS TOTP (Time-based One-Time Password) authenticator app. It generates 2FA codes by scanning QR codes or manual entry. Built with Swift 6, SwiftUI, and SwiftData. Targets iOS 26.0+.

## Build & Run

The Xcode project is generated from `project.yml` using XcodeGen:

```bash
xcodegen generate   # Regenerate .xcodeproj from project.yml
```

Run `xcodegen generate` after modifying `project.yml` or adding/removing source files.

Build and run via Xcode or:
```bash
xcodebuild -project Kagimori.xcodeproj -scheme Kagimori -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

There are no tests, linters, or formatters configured yet.

### Installing to a physical device

Build and install onto a paired iPhone (dev and prod side-by-side):

```bash
make devices   # first time: list paired devices, copy your iPhone's UDID
make setup     # first time: save the UDID to .install.env (git-ignored)
make dev       # Debug build  -> com.kagimori.app.debug ("Kagimori Dev")
make prod      # Release build -> com.kagimori.app ("Kagimori")
make both      # dev then prod
```

Pair the phone over Wi-Fi once in Xcode (Devices & Simulators) so no cable is
needed. Builds are signed Automatic with team `84QSJK68P2` and remain valid ~1 year.

## Architecture

**Data flow**: Secrets are stored in Keychain (never in SwiftData). Account metadata (issuer, name, algorithm, digits, period) is persisted via SwiftData `@Model`. The `keychainKey` on `OTPAccount` links the two.

**TOTP generation**: `TOTPGenerator` implements RFC 6238 using CryptoKit HMAC (SHA1/SHA256/SHA512). `Base32` decodes the shared secret. `OTPAuthURI` parses `otpauth://totp/...` URIs from QR codes.

**Views**: `AccountListView` is the root — uses `TimelineView` with 1-second ticks to refresh codes. `AddAccountView` switches between `QRScannerView` (AVFoundation camera) and `ManualEntryView` (form). `CodeCardView` renders each account's code with a countdown ring.

**QR scanning**: `QRScannerView` wraps a UIKit `AVCaptureSession` via `UIViewControllerRepresentable`. Scans for `otpauth://` prefixed metadata.

## Key Conventions

- Swift 6 strict concurrency (`SWIFT_VERSION: "6.0"`)
- All logic types (`TOTPGenerator`, `Base32`, `KeychainService`, `OTPAuthURI`) are caseless enums used as namespaces
- The app uses iOS 26 Liquid Glass effects (`.glassEffect`, `.buttonStyle(.glass)`)
- `project.yml` has a `postGenCommand` that patches the pbxproj to set the icon file type to `folder.iconcomposer`
