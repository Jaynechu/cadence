#!/bin/bash
# Build cadence and sign it with a stable local identity so macOS privacy
# grants (Full Disk Access, Reminders, Calendars) survive rebuilds.
set -e
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
IDENTITY="${CADENCE_SIGN_IDENTITY:-cadence-local}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/cadence"
codesign --force --sign "$IDENTITY" --identifier com.cadence.cli "$BIN"
codesign -dr - "$BIN" 2>&1 | grep designated
