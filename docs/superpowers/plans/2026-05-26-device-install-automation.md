# Device Install Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make dev` / `make prod` / `make both` commands that build the right Kagimori config and wirelessly install it onto a personal iPhone via `devicectl`.

**Architecture:** A committed `Makefile` is the user-facing entry point; it delegates the build+install logic to a committed `Scripts/install.sh` that takes a configuration name. The target device UDID lives in a git-ignored `.install.env`. No archiving/IPA — the built `.app` is installed directly.

**Tech Stack:** GNU Make, Bash, XcodeGen, `xcodebuild`, `xcrun devicectl` (Xcode 26).

Reference spec: `docs/superpowers/specs/2026-05-26-device-install-automation-design.md`

---

### Task 1: Git-ignore build artifacts and device config

**Files:**
- Modify (or create): `.gitignore`

- [ ] **Step 1: Check current .gitignore**

Run: `cat .gitignore 2>/dev/null || echo "NO GITIGNORE"`
Note whether the file exists and what it already contains, so the entries below aren't duplicated.

- [ ] **Step 2: Append ignore entries**

Add these lines to `.gitignore` (append; do not remove existing entries):

```gitignore
# Device install automation
.install.env
.build/
```

- [ ] **Step 3: Verify**

Run: `git check-ignore .install.env .build/ && echo OK`
Expected: prints the two paths followed by `OK`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore device install env and local build dir"
```

---

### Task 2: Device-listing helper script

This task creates `Scripts/install.sh` with only the `devices` subcommand working first, so device discovery is verifiable before the build flow is added.

**Files:**
- Create: `Scripts/install.sh`

- [ ] **Step 1: Create the script skeleton with `devices` support**

Create `Scripts/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (script lives in <root>/Scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.install.env"
DERIVED_DATA="$ROOT_DIR/.build"
SCHEME="Kagimori"

list_devices() {
  echo "Paired devices (name — identifier):"
  xcrun devicectl list devices
  echo
  echo "Copy your iPhone's identifier (UDID), then run: make setup"
}

usage() {
  echo "Usage: $0 {devices|setup|Debug|Release}" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  devices) list_devices ;;
  *) usage ;;
esac
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x Scripts/install.sh`

- [ ] **Step 3: Verify devices subcommand**

Run: `./Scripts/install.sh devices`
Expected: prints "Paired devices" then the `devicectl list devices` table (a table of connected/paired devices; may be empty if none paired, which is fine). No error exit.

- [ ] **Step 4: Verify usage guard**

Run: `./Scripts/install.sh bogus; echo "exit=$?"`
Expected: prints the `Usage:` line and `exit=2`.

- [ ] **Step 5: Commit**

```bash
git add Scripts/install.sh
git commit -m "feat: add install script with device listing"
```

---

### Task 3: Device UDID config (`setup` + loader)

**Files:**
- Modify: `Scripts/install.sh`

- [ ] **Step 1: Add a `setup` function and env loader**

In `Scripts/install.sh`, add these two functions after `list_devices()`:

```bash
write_setup() {
  local udid="${UDID:-}"
  if [[ -z "$udid" ]]; then
    read -r -p "Enter your iPhone UDID (see 'make devices'): " udid
  fi
  if [[ -z "$udid" ]]; then
    echo "No UDID provided." >&2
    exit 1
  fi
  printf 'DEVICE_UDID=%s\n' "$udid" > "$ENV_FILE"
  echo "Wrote $ENV_FILE"
}

require_device() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "No device configured. Run 'make devices' then 'make setup'." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  if [[ -z "${DEVICE_UDID:-}" ]]; then
    echo "DEVICE_UDID missing/empty in $ENV_FILE. Run 'make setup'." >&2
    exit 1
  fi
}
```

- [ ] **Step 2: Wire `setup` into the case statement**

In the `case "$cmd"` block, add a `setup` branch:

```bash
  devices) list_devices ;;
  setup) write_setup ;;
  *) usage ;;
```

- [ ] **Step 3: Verify setup writes the file**

Run: `UDID=TEST-UDID-123 ./Scripts/install.sh setup && cat .install.env`
Expected: prints `Wrote .../.install.env` then `DEVICE_UDID=TEST-UDID-123`.

- [ ] **Step 4: Verify require_device error path**

Run: `mv .install.env .install.env.bak; ./Scripts/install.sh setup <<< "" ; echo "exit=$?"; mv .install.env.bak .install.env 2>/dev/null || true`
Expected: with empty input, prints "No UDID provided." and a non-zero exit. (This confirms the empty-input guard.) Restore any backup afterward.

- [ ] **Step 5: Remove the test env file so it isn't left around**

Run: `rm -f .install.env`
(`.install.env` is git-ignored, so nothing to commit for it.)

- [ ] **Step 6: Commit**

```bash
git add Scripts/install.sh
git commit -m "feat: add device UDID setup and config loader"
```

---

### Task 4: Build-and-install flow

**Files:**
- Modify: `Scripts/install.sh`

- [ ] **Step 1: Add the install function**

In `Scripts/install.sh`, add after `require_device()`:

```bash
build_and_install() {
  local config="$1"   # Debug | Release
  require_device

  echo "==> Regenerating project"
  xcodegen generate

  echo "==> Building $config for device"
  xcodebuild \
    -project Kagimori.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$config" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build

  local app_path="$DERIVED_DATA/Build/Products/${config}-iphoneos/${SCHEME}.app"
  if [[ ! -d "$app_path" ]]; then
    echo "Built app not found at: $app_path" >&2
    exit 1
  fi

  echo "==> Installing to device $DEVICE_UDID"
  xcrun devicectl device install app --device "$DEVICE_UDID" "$app_path"
  echo "==> Done: $config installed."
}
```

- [ ] **Step 2: Wire `Debug`/`Release` into the case statement**

Update the `case "$cmd"` block:

```bash
  devices) list_devices ;;
  setup) write_setup ;;
  Debug|Release) build_and_install "$cmd" ;;
  *) usage ;;
```

- [ ] **Step 3: Verify the no-device guard fires before building**

Run: `mv .install.env .install.env.bak 2>/dev/null; ./Scripts/install.sh Release; echo "exit=$?"; mv .install.env.bak .install.env 2>/dev/null || true`
Expected: prints "No device configured. Run 'make devices' then 'make setup'." and a non-zero exit, WITHOUT starting an xcodebuild. (Confirms `require_device` runs first.)

- [ ] **Step 4: Syntax-check the script**

Run: `bash -n Scripts/install.sh && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 5: Commit**

```bash
git add Scripts/install.sh
git commit -m "feat: build config and install to device via devicectl"
```

---

### Task 5: Makefile front-end

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create the Makefile**

Create `Makefile`:

```makefile
.PHONY: help dev prod both devices setup

help:
	@echo "Kagimori device install:"
	@echo "  make dev      Build Debug   and install com.kagimori.app.debug"
	@echo "  make prod     Build Release and install com.kagimori.app"
	@echo "  make both     Install dev then prod (side-by-side)"
	@echo "  make devices  List paired devices and their UDIDs"
	@echo "  make setup    Save your iPhone UDID to .install.env"

dev:
	./Scripts/install.sh Debug

prod:
	./Scripts/install.sh Release

both: dev prod

devices:
	./Scripts/install.sh devices

setup:
	./Scripts/install.sh setup
```

- [ ] **Step 2: Verify default/help target**

Run: `make help`
Expected: prints the help listing above. (Make uses tabs for recipe indentation — if you get "missing separator", the recipe lines need real tabs.)

- [ ] **Step 3: Verify `make devices` delegates correctly**

Run: `make devices`
Expected: same output as `./Scripts/install.sh devices` (the devicectl device table).

- [ ] **Step 4: Verify a build target reaches the device guard**

Run: `rm -f .install.env; make prod; echo "exit=$?"`
Expected: the "No device configured..." message and non-zero exit (no build started).

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile for dev/prod device installs"
```

---

### Task 6: Document the workflow

**Files:**
- Modify: `CLAUDE.md` (add a "Device Install" section under Build & Run)

- [ ] **Step 1: Add documentation**

In `CLAUDE.md`, immediately after the existing "Build & Run" section's xcodebuild block, add:

```markdown
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
```

- [ ] **Step 2: Verify the section renders**

Run: `grep -n "Installing to a physical device" CLAUDE.md`
Expected: one matching line.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document make dev/prod device install workflow"
```

---

### Task 7: End-to-end manual verification (requires the physical phone)

This task is not automatable in CI; it confirms the real outcome and must be run by the user with their iPhone paired and unlocked.

- [ ] **Step 1: First-time device setup**

```bash
make devices
make setup     # paste the iPhone UDID when prompted
```
Expected: `.install.env` created with the real UDID.

- [ ] **Step 2: Install the dev build**

Run: `make dev`
Expected: xcodegen runs, Debug build succeeds, `devicectl` reports the app installed. "Kagimori Dev" appears on the home screen and opens.

- [ ] **Step 3: Install the prod build**

Run: `make prod`
Expected: Release build succeeds and installs. "Kagimori" appears alongside "Kagimori Dev" (separate bundle IDs), and opens.

- [ ] **Step 4: Confirm side-by-side**

Verify both "Kagimori" and "Kagimori Dev" icons are present and each launches independently. No commit needed (verification only).
```
