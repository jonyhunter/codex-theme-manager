import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = await fs.readFile(path.resolve(here, "../scripts/injector.mjs"), "utf8");

assert.match(
  source,
  /const LOOPBACK_HOSTS = new Set\(\[[^\]]*"127\.0\.0\.1"[^\]]*"localhost"/,
  "The Windows injector must restrict debugger connections to loopback hosts.",
);
assert.match(
  source,
  /url\.protocol !== "ws:"[\s\S]{0,180}!LOOPBACK_HOSTS\.has\(url\.hostname\)[\s\S]{0,120}Number\(url\.port\) !== port/,
  "The debugger URL validator must enforce protocol, host, and expected port.",
);
assert.match(
  source,
  /debuggerUrl\.pathname === `\/devtools\/page\/\$\{item\.id\}`/,
  "Target IDs must match their exact CDP page endpoint.",
);
assert.match(
  source,
  /class BrowserIdentityAnchor[\s\S]{0,1800}CDP browser identity/,
  "A Windows session must stay anchored to the browser identity discovered at startup.",
);
assert.match(
  source,
  /markers\.settings \|\|[\s\S]{0,160}markers\.shell && markers\.sidebar/,
  "A renderer must expose the Codex shell or settings markers before injection.",
);
assert.match(
  source,
  /session\.on\("Page\.loadEventFired"[\s\S]{0,300}applyToSession\(session, payload\)/,
  "The watcher must reapply the theme after a renderer navigation.",
);
assert.match(
  source,
  /finally\s*\{[\s\S]{0,160}identityAnchor\.close\(\);[\s\S]{0,160}sessions\.values\(\)/,
  "Watcher shutdown must release the identity anchor and all CDP sessions.",
);
assert.match(
  source,
  /options\.mode === "self-test"[\s\S]{0,2000}CDP URL validation accepted an unsafe URL/,
  "The packaged injector must retain its executable CDP validation self-test.",
);

console.log("PASS: Windows injection validates page identity, loopback CDP, reloads, and cleanup.");
