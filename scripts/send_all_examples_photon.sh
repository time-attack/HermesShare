#!/usr/bin/env bash
# Export sample JSONs (via XCTest) and send every HermesShare example card via Photon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${SIMULATOR_UDID:-DC20D61F-1BD5-4E2F-A312-EEBC07529F0A}"
DD="$ROOT/build/DD"
BATCH="/tmp/hermes-photon-batch"
THUMBS="/tmp/hermes-photon-thumbs"
SEND_SCRIPT="$ROOT/scripts/send_card_photon.mjs"
SIDECAR="${PHOTON_SIDECAR:-$HOME/.hermes/hermes-agent/plugins/platforms/photon/sidecar}"
CARD_HOST="${HERMES_CARD_HOST:-https://raw.githubusercontent.com/time-attack/HermesShare/main/docs/card-stub.json}"

set -a
source "$HOME/.hermes/.env"
set +a

TO="${PHOTON_SEND_TO:-${PHOTON_ALLOWED_USERS%%,*}}"
if [[ -z "$TO" ]]; then
  echo "Set PHOTON_ALLOWED_USERS or PHOTON_SEND_TO in ~/.hermes/.env"
  exit 1
fi

mkdir -p "$BATCH" "$THUMBS"

echo "==> Exporting HermesLayout JSON samples..."
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  -only-testing:HermesSharedTests/HermesReadmeScreenshotTests/testDumpSampleJSONsForPhoton \
  test -quiet 2>&1 | tail -5

COUNT=$(ls -1 "$BATCH"/*.json 2>/dev/null | wc -l | tr -d ' ')
echo "    $COUNT JSON files in $BATCH"

echo "==> Card host: $CARD_HOST"

SEND="$SIDECAR/send_batch_card.mjs"
cp "$SEND_SCRIPT" "$SEND"

SENT=0
FAILED=0
LOG="/tmp/hermes-photon-send.log"
: > "$LOG"

cd "$SIDECAR"
export PHOTON_PROJECT_ID PHOTON_PROJECT_SECRET

for json in "$BATCH"/*.json; do
  base=$(basename "$json" .json)
  thumb="$THUMBS/$base.jpg"
  echo "==> [$base] thumbnail + send..."
  python3 "$ROOT/scripts/make_thumbnail.py" "$json" "$thumb"
  compact=$(python3 -c "import json; print(json.dumps(json.load(open('$json')), separators=(',', ':')))")
  out=$(node send_batch_card.mjs "$compact" "$TO" "$CARD_HOST" "$thumb" 2>&1) || true
  echo "$out" >>"$LOG"
  if echo "$out" | rg -q "SEND FAILED"; then
    echo "    FAILED"
    FAILED=$((FAILED + 1))
  elif echo "$out" | rg -q "^SENT:"; then
    echo "    SENT"
    SENT=$((SENT + 1))
  else
    echo "    FAILED (no SENT line)"
    FAILED=$((FAILED + 1))
  fi
  # Photon rate limit: ~10 msgs / 30s — pace at 3s between cards.
  sleep 3
done

rm -f "$SIDECAR/send_batch_card.mjs"
echo ""
echo "Done: $SENT sent, $FAILED failed (details: $LOG)"
rg "SEND FAILED|SENT:" "$LOG" | tail -20
