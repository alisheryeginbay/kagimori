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

usage() {
  echo "Usage: $0 {devices|setup|Debug|Release}" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  devices) list_devices ;;
  setup) write_setup ;;
  *) usage ;;
esac
