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

write_setup() {
  local udid="${UDID:-}"
  if [[ -z "$udid" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Enter your iPhone UDID (see 'make devices'): " udid
    else
      echo "No UDID provided and stdin is not a terminal. Use: UDID=<udid> make setup" >&2
      exit 1
    fi
  fi
  if [[ -z "$udid" ]]; then
    echo "No UDID provided." >&2
    exit 1
  fi
  if [[ ! "$udid" =~ ^[0-9A-Za-z-]+$ ]]; then
    echo "UDID looks wrong (expected alphanumeric with hyphens): '$udid'" >&2
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
  DEVICE_UDID="$(grep -E '^DEVICE_UDID=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '"')"
  if [[ -z "${DEVICE_UDID:-}" ]]; then
    echo "DEVICE_UDID missing/empty in $ENV_FILE. Run 'make setup'." >&2
    exit 1
  fi
}

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
  if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$app_path"; then
    echo "Install failed. Check that the device is unlocked, on Wi-Fi, and paired in Xcode." >&2
    exit 1
  fi
  echo "==> Done: $config installed."
}

usage() {
  echo "Usage: $0 {devices|setup|Debug|Release}" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  devices) list_devices ;;
  setup) write_setup ;;
  Debug|Release) build_and_install "$cmd" ;;
  *) usage ;;
esac
