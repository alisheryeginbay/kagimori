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
