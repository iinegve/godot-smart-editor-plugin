#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDON_NAME="smart-editor-plugin"
ADDON_DIR="$REPO_ROOT/addons/$ADDON_NAME"
OUT="${1:-$REPO_ROOT/$ADDON_NAME-local.zip}"
TMP_DIR="$(mktemp -d)"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -d "$ADDON_DIR" ]]; then
	echo "Addon directory not found: $ADDON_DIR" >&2
	exit 1
fi

rm -f "$OUT"
mkdir -p "$TMP_DIR/addons"
rsync -a --exclude='media/' "$ADDON_DIR" "$TMP_DIR/addons/"

(
	cd "$TMP_DIR"
	zip -qr "$OUT" addons
)

echo "$OUT"
