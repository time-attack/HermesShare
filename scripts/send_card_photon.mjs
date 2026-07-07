#!/usr/bin/env node
// Send a HermesShare interactive card into iMessage via Photon (spectrum-ts customizedMiniApp).
//
// Usage:
//   node send_card_photon.mjs '<layout-json>' <recipient-e164> <https-url> [thumbnail.jpg]
//
// Env:
//   PHOTON_PROJECT_ID, PHOTON_PROJECT_SECRET — required
//   HERMES_TEAM_ID — Apple team ID (default: com.hermesshare.app project value)
//   HERMES_EXTENSION_BUNDLE_ID — extension bundle (default: com.hermesshare.app.MessagesExtension)
//
// Thumbnail must be JPEG (~600×400). Generate with: python3 scripts/make_thumbnail.py card.json thumb.jpg

import { Spectrum } from "spectrum-ts";
import { imessage, customizedMiniApp } from "spectrum-ts/providers/imessage";

const TEAM_ID = process.env.HERMES_TEAM_ID || "YOUR_TEAM_ID";
const EXTENSION_BUNDLE_ID =
  process.env.HERMES_EXTENSION_BUNDLE_ID || "com.hermesshare.app.MessagesExtension";

function base64url(jsonString) {
  return Buffer.from(jsonString, "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

const [, , layoutArg, toArg, hostArg, thumbArg] = process.argv;
if (!layoutArg || !toArg || !hostArg) {
  console.error(
    "Usage: node send_card_photon.mjs '<layout-json>' <to-e164> <https-url> [thumbnail.jpg]"
  );
  process.exit(1);
}

const layout = JSON.parse(layoutArg);
const caption = layout.title || "HermesShare";
const subcaption = layout.subtitle;

const PROJECT_ID = process.env.PHOTON_PROJECT_ID;
const PROJECT_SECRET = process.env.PHOTON_PROJECT_SECRET;
if (!PROJECT_ID || !PROJECT_SECRET) {
  console.error("Set PHOTON_PROJECT_ID and PHOTON_PROJECT_SECRET.");
  process.exit(1);
}

if (TEAM_ID === "YOUR_TEAM_ID") {
  console.error("Set HERMES_TEAM_ID to your Apple Developer team ID.");
  process.exit(1);
}

const app = await Spectrum({
  projectId: PROJECT_ID,
  projectSecret: PROJECT_SECRET,
  providers: [imessage.config()],
});

try {
  const im = imessage(app);
  const space = await im.space.get(`any;-;${toArg}`);

  const payload = base64url(JSON.stringify(layout));
  const sep = hostArg.includes("?") ? "&" : "?";
  const url = `${hostArg}${sep}p=${payload}`;

  let messageLayout;
  const imageTitlePlaceholder = "\u2060";
  if (thumbArg) {
    const { readFileSync } = await import("node:fs");
    messageLayout = {
      image: new Uint8Array(readFileSync(thumbArg)),
      imageTitle: imageTitlePlaceholder,
      caption,
    };
    if (subcaption) messageLayout.subcaption = subcaption;
  } else {
    messageLayout = { caption, subcaption };
  }

  const sent = await space.send(
    customizedMiniApp({
      appName: "HermesShare",
      extensionBundleId: EXTENSION_BUNDLE_ID,
      teamId: TEAM_ID,
      url,
      layout: messageLayout,
    })
  );
  console.log("SENT:", JSON.stringify(sent));
} catch (e) {
  console.error("SEND FAILED:", e?.message || e);
  process.exitCode = 1;
} finally {
  await app.stop();
}
