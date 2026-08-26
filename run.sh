#!/bin/zsh
# Build Accent and launch it in the iOS simulator.
# Usage: ./run.sh
set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

SIM_UDID="473019D8-0FC1-4925-8AA9-BB213E0316B5"   # iPhone 17 Pro, iOS 26.2
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
open -a Simulator

echo "▸ Installing…"
xcrun simctl install "$SIM_UDID" "$APP_PATH"

echo "▸ Launching…"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo "✓ Accent is running. Tip: 'say -r 140 \"your sentence\"' on the Mac feeds the sim mic."
