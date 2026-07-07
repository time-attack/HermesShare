#!/usr/bin/env bash
# Send picture-option + collapsible demo cards via Photon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${SIMULATOR_UDID:-DC20D61F-1BD5-4E2F-A312-EEBC07529F0A}"
DD="$ROOT/build/DD"
BATCH="/tmp/hermes-picture-demo-batch"
THUMBS="/tmp/hermes-picture-demo-thumbs"
SIDECAR="${PHOTON_SIDECAR:-$HOME/.hermes/hermes-agent/plugins/platforms/photon/sidecar}"
PORT="${HERMES_TUNNEL_PORT:-8934}"
SEND_SCRIPT="$ROOT/scripts/send_card_photon.mjs"

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

echo "==> Starting static server on :$PORT..."
pkill -f "http.server $PORT" 2>/dev/null || true
python3 -m http.server "$PORT" --directory "$BATCH" >/tmp/hermes-picture-http.log 2>&1 &
HTTP_PID=$!
sleep 1

echo "==> Starting cloudflared tunnel..."
pkill -f "cloudflared tunnel --url http://localhost:$PORT" 2>/dev/null || true
cloudflared tunnel --url "http://localhost:$PORT" >/tmp/hermes-picture-tunnel.log 2>&1 &
TUNNEL_PID=$!

HOST=""
for _ in $(seq 1 30); do
  HOST=$(rg -o 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/hermes-picture-tunnel.log 2>/dev/null | head -1 || true)
  [[ -n "$HOST" ]] && break
  sleep 1
done
if [[ -z "$HOST" ]]; then
  echo "Failed to get tunnel URL"
  kill "$HTTP_PID" "$TUNNEL_PID" 2>/dev/null || true
  exit 1
fi
echo "    Tunnel: $HOST/card.json"

cleanup() { kill "$HTTP_PID" "$TUNNEL_PID" 2>/dev/null || true; }
trap cleanup EXIT

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
  out=$(node send_picture_demo.mjs "$compact" "$TO" "$HOST/card.json" "$thumb" 2>&1) || true
  echo "$out"
  echo "$out" | rg -q "^SENT:" && SENT=$((SENT + 1))
  sleep 3
done

rm -f "$SIDECAR/send_picture_demo.mjs"
echo "Done: $SENT / $(ls -1 "$BATCH"/*.json | wc -l | tr -d ' ') sent to $TO"
