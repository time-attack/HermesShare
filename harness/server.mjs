// server.mjs — Hermes agent harness server.
//
// One process, two audiences:
//   • The agent (localhost): POSTs state/todos/screenshots to /agent/*  (no auth)
//   • The phone (LAN):       pairs via /api/pair, then streams state over /ws
//
// Wire format matches AgentHarnessModels.swift in the HermesShare Shared package.

import { createServer } from "node:http";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { networkInterfaces } from "node:os";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.HARNESS_PORT || 8642);
const STATE_DIR = join(homedir(), ".hermes-harness");
const TOKENS_FILE = join(STATE_DIR, "tokens.json");

// ---------------------------------------------------------------- pairing

mkdirSync(STATE_DIR, { recursive: true });

const pairingCode = String(Math.floor(100000 + Math.random() * 900000));

/** @type {Record<string, {deviceName: string, pairedAt: number}>} */
let tokens = {};
if (existsSync(TOKENS_FILE)) {
  try { tokens = JSON.parse(readFileSync(TOKENS_FILE, "utf8")); } catch { tokens = {}; }
}
const saveTokens = () => writeFileSync(TOKENS_FILE, JSON.stringify(tokens, null, 2));
const isValidToken = (t) => typeof t === "string" && Object.hasOwn(tokens, t);

// ---------------------------------------------------------------- session state

const nowSec = () => Math.floor(Date.now() / 1000);

const newSession = (title = "Hermes Agent") => ({
  sessionID: randomUUID(),
  title,
  status: "idle",
  currentTask: null,
  currentAction: null,
  todos: [],
  screenshotSeq: 0,
  updatedAt: nowSec(),
});

let state = newSession();
let screenshot = null; // { buffer, contentType }

// ---------------------------------------------------------------- websocket fanout

const wss = new WebSocketServer({ noServer: true });

function broadcast(type) {
  const payload = JSON.stringify({ type, state });
  for (const client of wss.clients) {
    if (client.readyState === client.OPEN) client.send(payload);
  }
}

wss.on("connection", (socket, request) => {
  const device = tokens[socket.harnessToken]?.deviceName ?? "unknown device";
  log(`phone connected: ${device} (${request.socket.remoteAddress})`);
  socket.send(JSON.stringify({ type: "hello", state }));
  socket.on("close", () => log(`phone disconnected: ${device}`));
});

// Keep NAT/table entries warm and detect dead peers.
setInterval(() => {
  for (const client of wss.clients) {
    if (client.readyState === client.OPEN) {
      client.ping();
      client.send(JSON.stringify({ type: "ping" }));
    }
  }
}, 25_000);

// ---------------------------------------------------------------- http server

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const route = `${req.method} ${url.pathname}`;

  try {
    // ---------- phone-facing ----------
    if (route === "POST /api/pair") {
      const body = await readJSON(req);
      if (String(body.code).trim() !== pairingCode) {
        return sendJSON(res, 403, { error: "wrong pairing code" });
      }
      const token = randomBytes(24).toString("hex");
      tokens[token] = { deviceName: body.deviceName || "iPhone", pairedAt: nowSec() };
      saveTokens();
      log(`paired: ${tokens[token].deviceName}`);
      return sendJSON(res, 200, { token, title: state.title });
    }

    if (route === "GET /api/screenshot") {
      if (!isValidToken(url.searchParams.get("token"))) {
        return sendJSON(res, 403, { error: "bad token" });
      }
      if (!screenshot) return sendJSON(res, 404, { error: "no screenshot yet" });
      res.writeHead(200, {
        "Content-Type": screenshot.contentType,
        "Content-Length": screenshot.buffer.length,
        "Cache-Control": "no-store",
      });
      return res.end(screenshot.buffer);
    }

    // ---------- agent-facing (localhost only) ----------
    if (url.pathname.startsWith("/agent/")) {
      const remote = req.socket.remoteAddress ?? "";
      const isLocal = ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(remote);
      if (!isLocal) return sendJSON(res, 403, { error: "agent API is localhost-only" });
    }

    if (route === "POST /agent/state") {
      const body = await readJSON(req);
      if (body.newSession) {
        state = newSession(body.title || state.title);
        screenshot = null;
      }
      for (const key of ["title", "status", "currentTask", "currentAction", "todos"]) {
        if (key in body) state[key] = body[key];
      }
      state.updatedAt = nowSec();
      broadcast("state");
      return sendJSON(res, 200, { ok: true, state });
    }

    if (route === "POST /agent/screenshot") {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const buffer = Buffer.concat(chunks);
      if (buffer.length === 0) return sendJSON(res, 400, { error: "empty body" });
      const contentType = req.headers["content-type"] || "image/png";
      screenshot = { buffer, contentType };
      state.screenshotSeq += 1;
      state.updatedAt = nowSec();
      broadcast("state");
      return sendJSON(res, 200, { ok: true, screenshotSeq: state.screenshotSeq });
    }

    if (route === "POST /agent/end") {
      const body = await readJSON(req).catch(() => ({}));
      state.status = body.status || "done";
      if (body.currentAction !== undefined) state.currentAction = body.currentAction;
      state.updatedAt = nowSec();
      broadcast("sessionEnd");
      return sendJSON(res, 200, { ok: true });
    }

    if (route === "GET /agent/info") {
      return sendJSON(res, 200, {
        pairingCode,
        port: PORT,
        addresses: lanAddresses(),
        pairedDevices: Object.values(tokens).map((t) => t.deviceName),
        connectedClients: wss.clients.size,
        state,
      });
    }

    sendJSON(res, 404, { error: "not found" });
  } catch (err) {
    sendJSON(res, 500, { error: String(err?.message || err) });
  }
});

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  if (url.pathname !== "/ws" || !isValidToken(url.searchParams.get("token"))) {
    socket.write("HTTP/1.1 403 Forbidden\r\n\r\n");
    socket.destroy();
    return;
  }
  wss.handleUpgrade(request, socket, head, (ws) => {
    ws.harnessToken = url.searchParams.get("token");
    wss.emit("connection", ws, request);
  });
});

// ---------------------------------------------------------------- helpers

function readJSON(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}")); }
      catch (e) { reject(e); }
    });
    req.on("error", reject);
  });
}

function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
  res.end(body);
}

function lanAddresses() {
  return Object.values(networkInterfaces())
    .flat()
    .filter((i) => i && i.family === "IPv4" && !i.internal)
    .map((i) => i.address);
}

const log = (msg) => console.log(`[harness ${new Date().toLocaleTimeString()}] ${msg}`);

// ---------------------------------------------------------------- boot

server.listen(PORT, "0.0.0.0", () => {
  const addrs = lanAddresses();
  console.log("┌──────────────────────────────────────────────┐");
  console.log("│         Hermes Agent Harness Server          │");
  console.log("└──────────────────────────────────────────────┘");
  console.log(`  Pairing code : ${pairingCode}`);
  for (const a of addrs) console.log(`  Server URL   : http://${a}:${PORT}`);
  console.log(`  Agent API    : http://127.0.0.1:${PORT}/agent/*`);
  console.log("");
  console.log("  In the HermesShare app → Agent tab → Pair,");
  console.log("  enter the server URL and pairing code above.");
});
