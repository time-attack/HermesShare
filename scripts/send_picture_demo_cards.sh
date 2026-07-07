#!/usr/bin/env bash
# Send picture-option + collapsible demo cards via Photon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${SIMULATOR_UDID:-DC20D61F-1BD5-4E2F-A312-EEBC07529F0A}"
DD="$ROOT/build/DD"
BATCH="/tmp/hermes-picture-demo-batch"
THUMBS="/tmp/hermes-picture-demo-thumbs"
SEND_SCRIPT="$ROOT/scripts/send_card_photon.mjs"
SIDECAR="${PHOTON_SIDECAR:-$HOME/.hermes/hermes-agent/plugins/platforms/photon/sidecar}"
# Permanent https host — iOS probes MSMessage.url; dead tunnels cause "page couldn't load".
CARD_HOST="${HERMES_CARD_HOST:-https://raw.githubusercontent.com/time-attack/HermesShare/main/docs/card-stub.json}"

set -a
source "$HOME/.hermes/.env"
set +a

TO="${PHOTON_SEND_TO:-${PHOTON_ALLOWED_USERS%%,*}}"
export HERMES_TEAM_ID="${HERMES_TEAM_ID:-6PPS68Y9RP}"

mkdir -p "$BATCH" "$THUMBS"
rm -f "$BATCH"/*.json

echo "==> Exporting demo JSON fixtures..."
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:HermesSharedTests/HermesReadmeScreenshotTests/testDumpSampleJSONsForPhoton \
  test -quiet 2>&1 | tail -3

for name in demo_picture_restaurants demo_picture_flights demo_app_designs \
            demo_collapsible_trip sent_kyoto_catalog; do
  cp "/tmp/hermes-photon-batch/${name}.json" "$BATCH/" 2>/dev/null || \
    cp "$ROOT/Shared/Tests/HermesSharedTests/Fixtures/${name}.json" "$BATCH/"
done

echo "==> Card host: $CARD_HOST"

cp "$SEND_SCRIPT" "$SIDECAR/send_picture_demo.mjs"
cd "$SIDECAR"
export PHOTON_PROJECT_ID PHOTON_PROJECT_SECRET

SENT=0
for json in "$BATCH"/*.json; do
  base=$(basename "$json" .json)
  thumb="$THUMBS/$base.jpg"
  echo "==> [$base] send..."
  python3 "$ROOT/scripts/make_thumbnail.py" "$json" "$thumb"
  compact=$(python3 -c "import json; print(json.dumps(json.load(open('$json')), separators=(',', ':')))")
  out=$(node send_picture_demo.mjs "$compact" "$TO" "$CARD_HOST" "$thumb" 2>&1) || true
  echo "$out" | rg '^SENT:|SEND FAILED' || echo "$out" | tail -1
  echo "$out" | rg -q "^SENT:" && SENT=$((SENT + 1))
  sleep 3
done

rm -f "$SIDECAR/send_picture_demo.mjs"
echo "Done: $SENT / $(ls -1 "$BATCH"/*.json | wc -l | tr -d ' ') sent to $TO"
