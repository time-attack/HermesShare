# Hermes Agent Harness

Live tracking for a running Hermes agent, streamed to the HermesShare iOS app and a
**Live Activity** on the lock screen / Dynamic Island.

```text
Agent (this Mac)                      Phone (HermesShare app)
────────────────                      ───────────────────────
hermes-harness update ──► server ──►  WebSocket ──► Agent tab dashboard
hermes-harness screenshot  (8642)                └─► ActivityKit Live Activity
```

## Run the server

```bash
cd harness
npm install          # once
node hermes-harness.mjs serve
```

It prints a **6-digit pairing code** and the server URLs (LAN + Tailscale IPs).
Port is `8642` by default (`HARNESS_PORT` to change).

## Pair the phone

HermesShare app → **Agent** tab → **Pair** → enter the server URL and the code.
The token is persisted; the app reconnects automatically on next launch.

## Drive it from the agent

All agent endpoints are **localhost-only** — anything running on this Mac can post,
but nothing on the network can spoof the agent.

```bash
# start a fresh session (starts a new Live Activity on the phone)
node hermes-harness.mjs update --new-session \
  --title "Refactor payments module" --status working \
  --task "Update schema" --action "Editing models.py…" \
  --todos '[{"id":"1","content":"Update schema","status":"in_progress"},
            {"id":"2","content":"Run tests","status":"pending"}]'

# incremental updates (only pass what changed)
node hermes-harness.mjs update --action "Running pytest…"
node hermes-harness.mjs update --status waiting --action "Blocked: needs API key"

# push a preview image (computer-use / browser screenshot)
node hermes-harness.mjs screenshot /tmp/browser.png

# finish (Live Activity shows final state, dismisses after ~5 min)
node hermes-harness.mjs end --status done --action "All tasks complete"

node hermes-harness.mjs info    # pairing code, connected phones, current state
```

Raw HTTP works too: `POST /agent/state`, `POST /agent/screenshot` (raw image body),
`POST /agent/end`, `GET /agent/info` on `http://127.0.0.1:8642`.

### Todo status values

`pending` · `in_progress` · `completed` · `cancelled` — same vocabulary as the
agent's own todo tool, so lists can be forwarded verbatim. Cancelled items are
excluded from the progress fraction.

## Automatic updates from your Hermes agent (hooks)

You don't have to call the CLI by hand — the Hermes agent (`~/.hermes/hermes-agent`,
the `tui_gateway` service) streams its live activity via Hermes' built-in
**shell hooks**, configured in `~/.hermes/config.yaml`:

| Hermes event         | Bridge label | Effect |
|----------------------|--------------|--------|
| `pre_llm_call`       | `h-submit`   | New user turn → starts a fresh session + Live Activity, title from the user message |
| `post_tool_call`     | `h-tool`     | The `todo` tool's result mirrors the todo list; other tools set the current action |
| `post_llm_call`      | `h-stop`     | Turn finished → status `done` |
| `on_session_finalize`| `h-end`      | Session torn down (`/new`, GC, exit) → ends the Live Activity |

Bridge script: `~/.cursor/hooks/hermes-harness-bridge.py` (Hermes labels `h-*`).
Each `(event, command)` pair is allowlisted in `~/.hermes/shell-hooks-allowlist.json`
so the hooks fire non-interactively under the launchd-supervised gateway.

Because these hooks live in the Hermes agent's own config, only the Hermes agent
drives the phone — unrelated Cursor/Claude coding sessions never touch it, and no
workspace-scope filtering is needed.

Verify / manage with Hermes' own tooling:

```bash
hermes hooks list      # shows the 4 hooks + ✓ allowed
hermes hooks doctor    # exec bit, allowlist, JSON output smoke test
hermes gateway restart # reload hooks into the running gateway
```

A gateway that was already running when the hooks were added must be restarted
(`hermes gateway restart`) to register them.

## Background updates on the phone

Sideloaded builds have no APNs key, so Live Activity updates while the phone is
locked are driven by the app itself: the Agent tab's **Background updates** toggle
(on by default while connected) plays inaudible silence under the `audio` background
mode to keep the WebSocket alive. Turn it off in the ⋯ menu if you don't need
lock-screen updates.

## Files

- `server.mjs` — HTTP + WebSocket server, pairing, screenshot store
- `hermes-harness.mjs` — CLI (`serve`, `info`, `update`, `screenshot`, `end`)
- Tokens persist in `~/.hermes-harness/tokens.json`

Wire format lives in `Shared/Sources/HermesShared/AgentHarnessModels.swift` and is
covered by `AgentHarnessModelTests`.
