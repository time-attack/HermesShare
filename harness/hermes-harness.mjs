#!/usr/bin/env node
// hermes-harness — CLI for the Hermes agent harness.
//
//   hermes-harness serve                       start the harness server (foreground)
//   hermes-harness info                        pairing code, URLs, connected phones
//   hermes-harness update [options]            push a state update to paired phones
//       --title "Run title"                    session title (Live Activity header)
//       --status working|waiting|done|error|idle
//       --task "Current todo being worked"
//       --action "Running xcodebuild…"
//       --todos '[{"id":"1","content":"…","status":"in_progress"}]'
//       --todos-file path.json
//       --new-session                          start a fresh session (new Live Activity)
//   hermes-harness screenshot <image-path>     push a preview image (png/jpg)
//   hermes-harness end [--status done|error] [--action "wrap-up note"]
//
// The server must be running (hermes-harness serve). Agent endpoints are localhost-only.

import { readFileSync } from "node:fs";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PORT = Number(process.env.HARNESS_PORT || 8642);
const BASE = `http://127.0.0.1:${PORT}`;
const __dirname = dirname(fileURLToPath(import.meta.url));

const [cmd, ...rest] = process.argv.slice(2);

function parseFlags(args) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = args[i + 1];
      if (next === undefined || next.startsWith("--")) {
        flags[key] = true;
      } else {
        flags[key] = next;
        i++;
      }
    } else {
      positional.push(arg);
    }
  }
  return { flags, positional };
}

async function post(path, body, contentType = "application/json") {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body: contentType === "application/json" ? JSON.stringify(body) : body,
    });
  } catch {
    console.error(`error: harness server not reachable at ${BASE} — run \`hermes-harness serve\` first`);
    process.exit(2);
  }
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error(`error (${res.status}):`, json.error || json);
    process.exit(1);
  }
  return json;
}

switch (cmd) {
  case "serve": {
    await import(join(__dirname, "server.mjs"));
    break;
  }

  case "info": {
    try {
      const res = await fetch(`${BASE}/agent/info`);
      const info = await res.json();
      console.log(`pairing code : ${info.pairingCode}`);
      for (const a of info.addresses) console.log(`server url   : http://${a}:${info.port}`);
      console.log(`paired       : ${info.pairedDevices.join(", ") || "(none)"}`);
      console.log(`connected    : ${info.connectedClients} client(s)`);
      console.log(`session      : ${info.state.sessionID}`);
      console.log(`status       : ${info.state.status} — ${info.state.currentTask ?? "(no task)"}`);
    } catch {
      console.error(`error: harness server not reachable at ${BASE} — run \`hermes-harness serve\` first`);
      process.exit(2);
    }
    break;
  }

  case "update": {
    const { flags } = parseFlags(rest);
    const body = {};
    if (flags.title) body.title = flags.title;
    if (flags.status) body.status = flags.status;
    if (flags.task) body.currentTask = flags.task;
    if (flags.action) body.currentAction = flags.action;
    if (flags["new-session"]) body.newSession = true;
    if (flags.todos) body.todos = JSON.parse(flags.todos);
    if (flags["todos-file"]) body.todos = JSON.parse(readFileSync(flags["todos-file"], "utf8"));
    const out = await post("/agent/state", body);
    const s = out.state;
    console.log(`ok — ${s.status} | ${s.currentTask ?? "(no task)"} | todos ${s.todos.filter(t => t.status === "completed").length}/${s.todos.length}`);
    break;
  }

  case "screenshot": {
    const { positional } = parseFlags(rest);
    const file = positional[0];
    if (!file) { console.error("usage: hermes-harness screenshot <image-path>"); process.exit(1); }
    const buffer = readFileSync(file);
    const type = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp" }[extname(file).toLowerCase()] || "image/png";
    const out = await post("/agent/screenshot", buffer, type);
    console.log(`ok — screenshot #${out.screenshotSeq} (${(buffer.length / 1024).toFixed(0)} KB)`);
    break;
  }

  case "end": {
    const { flags } = parseFlags(rest);
    await post("/agent/end", {
      status: flags.status || "done",
      ...(flags.action ? { currentAction: flags.action } : {}),
    });
    console.log("ok — session ended");
    break;
  }

  default:
    console.log(readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").filter(l => l.startsWith("//")).map(l => l.slice(3)).join("\n"));
    process.exit(cmd ? 1 : 0);
}
