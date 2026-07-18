import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = await fs.readFile(path.resolve(here, "../scripts/injector.mjs"), "utf8");

assert.match(
  source,
  /const LOOPBACK_HOSTS = new Set\(\[[^\]]*"127\.0\.0\.1"[^\]]*"localhost"/,
  "The macOS injector must restrict debugger connections to loopback hosts.",
);
assert.match(
  source,
  /url\.protocol !== "ws:"[\s\S]{0,180}!LOOPBACK_HOSTS\.has\(url\.hostname\)[\s\S]{0,120}Number\(url\.port\) !== port/,
  "The debugger URL validator must enforce protocol, host, and expected port.",
);
assert.match(
  source,
  /item\.type !== "page" \|\| !item\.url\?\.startsWith\("app:\/\/"\)/,
  "Target discovery must ignore non-page and non-app targets.",
);
assert.match(
  source,
  /markers\.settings \|\|[\s\S]{0,160}markers\.shell && markers\.sidebar/,
  "A renderer must expose the Codex shell or settings markers before injection.",
);
assert.match(
  source,
  /session\.on\("Page\.loadEventFired"[\s\S]{0,260}applyToSession\(session, payload\)/,
  "The watcher must reapply the theme after a renderer navigation.",
);
assert.match(
  source,
  /rejected non-Codex app target/,
  "The watcher must explicitly reject auxiliary app targets.",
);
assert.match(
  source,
  /for \(const session of sessions\.values\(\)\) session\.close\(\)/,
  "Watcher shutdown must close all active CDP sessions.",
);
assert.doesNotMatch(
  source,
  /(^|[^\w])eval\s*\(/m,
  "Runtime state and payload handling must not use eval.",
);

console.log("PASS: macOS injection is loopback-only, shell-guarded, reload-aware, and cleaned up.");
