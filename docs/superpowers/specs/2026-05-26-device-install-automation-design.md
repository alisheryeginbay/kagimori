# Device Install Automation — Design

**Date:** 2026-05-26
**Status:** Approved

## Goal

Provide a convenient, elegant way to build and install Kagimori onto a personal
iPhone in both **dev** and **prod** flavors, without manual Xcode clicking. Because
the app is a daily-use 2FA authenticator, reliability and offline operation matter:
the installed build must not silently expire.

## Decisions & Rationale

- **Direct install for both configs; no TestFlight.** Development/release builds signed
  with the paid developer account (team `84QSJK68P2`) stay valid ~1 year. TestFlight
  builds expire after 90 days — unacceptable for an authenticator you depend on.
- **Manual `make` commands, not git hooks or schedules.** The phone must be reachable
  at install time; running on commit/push is fragile (slow builds, silent signing
  failures, device not present). Explicit commands = fewest moving parts.
- **No archiving / IPA export.** For personal direct install, building the config and
  pushing the resulting `.app` via `devicectl` is sufficient and far simpler than
  archive + export-options-plist flows. Signing stays `Automatic`.
- **Wireless via `xcrun devicectl`.** After pairing the phone once over Wi-Fi in Xcode,
  no cable is needed.

## Components

### `Makefile` (committed)
User-facing entry point. Targets:

- `make dev` — Debug config → installs `com.kagimori.app.debug` ("Kagimori Dev")
- `make prod` — Release config → installs `com.kagimori.app` ("Kagimori")
- `make both` — runs `dev` then `prod` (side-by-side installs; distinct bundle IDs)
- `make devices` — lists paired devices and their UDIDs (setup helper)
- `make setup` — writes the chosen device UDID into the git-ignored config file

Each of `dev`/`prod` delegates to `Scripts/install.sh` with the configuration name.

### `Scripts/install.sh` (committed)
Thin script that performs, given a configuration argument (`Debug`|`Release`):

1. `xcodegen generate` — keep `.xcodeproj` in sync with `project.yml`.
2. `xcodebuild -scheme Kagimori -configuration <config> -destination 'generic/platform=iOS' -derivedDataPath <dd> build`
   — produces a device `.app`.
3. Resolve the built `.app` path under the derived-data `Build/Products/<config>-iphoneos/` dir.
4. `xcrun devicectl device install app --device <UDID> <app-path>`.

Fails fast with a clear message at each step (no device configured, build failure,
app bundle not found).

### `.install.env` (git-ignored)
Single line: `DEVICE_UDID=<udid>`. Read by `install.sh`. Populated via `make setup`
or by hand. Added to `.gitignore`.

## Data Flow

```
make prod
  └─ Scripts/install.sh Release
       ├─ source .install.env  → DEVICE_UDID
       ├─ xcodegen generate
       ├─ xcodebuild ... -configuration Release build  → DerivedData/.../Release-iphoneos/Kagimori.app
       └─ xcrun devicectl device install app --device $DEVICE_UDID <Kagimori.app>
```

## Error Handling

- Missing/empty `.install.env` or `DEVICE_UDID` → print instructions to run
  `make devices` then `make setup`, exit non-zero.
- `xcodebuild` non-zero exit → propagate, stop (no install attempt).
- Built `.app` not found at expected path → error naming the searched path.
- `devicectl install` failure (device offline/unpaired) → surface devicectl's error,
  hint to check Wi-Fi pairing / unlock device.

## Out of Scope (YAGNI)

- TestFlight / App Store Connect upload.
- IPA export and ad-hoc distribution profiles.
- Multi-device fan-out (single personal device assumed).
- Automatic triggering (hooks, schedules, CI).

## First-Time Setup (documented in README or Makefile help)

1. Pair phone with Mac over Wi-Fi once via Xcode (Devices & Simulators).
2. `make devices` → copy the phone's UDID.
3. `make setup` (or edit `.install.env`).
4. `make dev` / `make prod` thereafter.
