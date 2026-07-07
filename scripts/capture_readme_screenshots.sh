#!/usr/bin/env bash
# Capture README screenshots: Messages.app composites + optional isolated card renders.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${SIMULATOR_UDID:-DC20D61F-1BD5-4E2F-A312-EEBC07529F0A}"
DD="$ROOT/build/DD"
OUT="$ROOT/docs/screenshots"

mkdir -p "$OUT/imessage"

echo "==> Booting simulator $UDID..."
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Building & installing host app + extension..."
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" build -quiet

APP="$DD/Build/Products/Debug-iphonesimulator/HermesShare.app"
xcrun simctl install "$UDID" "$APP"

echo "==> Compositing Messages.app screenshots (real chrome + Hermes bubbles/cards)..."
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:HermesShareUITests/MessagesScreenshotCompositor/testCompositeMessagesScreenshots \
  test 2>&1 | tail -15

echo "==> Generating isolated card PNGs (reference / docs)..."
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:HermesSharedTests/HermesReadmeScreenshotTests/testGenerateReadmeGallery \
  test 2>&1 | tail -10

echo "==> Done."
echo "    Messages.app shots: $OUT/imessage/"
ls -la "$OUT/imessage/"
