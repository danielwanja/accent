#!/bin/zsh
# Build Accent and launch it in the iOS simulator.
# Usage: ./run.sh
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
if [[ -z "${SIM_UDID:-}" ]]; then
  SIM_UDID=$(xcrun simctl list devices available -j | xcrun python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get("com.apple.CoreSimulator.SimRuntime.iOS-26-2", [])
print(next((d["udid"] for d in devices if d["name"] == "iPhone 17 Pro"), ""))
')
fi
if [[ -z "$SIM_UDID" ]]; then
  echo "Install an iPhone 17 Pro / iOS 26.2 simulator, or set SIM_UDID to an installed device." >&2
  exit 1
fi
BUNDLE_ID="com.n-so.accent"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_DIR"

echo "▸ Building…"
xcodebuild -project Accent.xcodeproj \
  -scheme Accent \
  -destination "id=$SIM_UDID" \
  -derivedDataPath build \
  build | tail -5

APP_PATH="build/Build/Products/Debug-iphonesimulator/Accent.app"

echo "▸ Booting simulator…"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$SIM_UDID" -b
open -a Simulator

echo "▸ Installing…"
xcrun simctl install "$SIM_UDID" "$APP_PATH"

echo "▸ Launching…"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo "✓ Accent is running. Tip: 'say -r 140 \"your sentence\"' on the Mac feeds the sim mic."
