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
