import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  compareVersions,
  validateCatalog,
  validateFeed,
} from "../../script/update-feed.mjs";
import {
  UPDATE_PUBLIC_KEY,
  checkForUpdates,
  compareVersions as compareWindowsVersions,
} from "../../windows/scripts/update-client.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

test("signed update metadata is valid and shared by both platforms", () => {
  assert.equal(compareVersions("1.7.0", "1.6.1"), 1);
  assert.equal(compareVersions("1.7.0", "1.7.0"), 0);
  assert.equal(compareWindowsVersions("1.6.1", "1.7.0"), -1);
  assert.throws(() => compareVersions("1.7", "1.7.0"));

  const feed = validateFeed(JSON.parse(readFileSync(
    path.join(repositoryRoot, "updates/stable.json"),
    "utf8",
  )));
  validateCatalog(JSON.parse(readFileSync(
    path.join(repositoryRoot, "updates/themes.json"),
    "utf8",
  )));
  const publicKey = JSON.parse(readFileSync(
    path.join(repositoryRoot, "updates/public-key.json"),
    "utf8",
  ));
  assert.equal(feed.version, "1.6.1");
  assert.deepEqual(UPDATE_PUBLIC_KEY, publicKey);

  const output = execFileSync(
    process.execPath,
    [path.join(repositoryRoot, "script/update-feed.mjs"), "validate"],
    { cwd: repositoryRoot, encoding: "utf8" },
  );
  assert.match(output, /signed update feed/);
});

test("Windows client verifies the detached feed and catalog signatures", async () => {
  const feedURL = "https://fixture.local/stable.json";
  const themeURL =
    "https://raw.githubusercontent.com/houyuhang915-sudo/Codex-Skin-Manager/main/updates/themes.json";
  const fixtures = new Map([
    [feedURL, readFileSync(path.join(repositoryRoot, "updates/stable.json"))],
    [feedURL + ".sig", readFileSync(path.join(repositoryRoot, "updates/stable.json.sig"))],
    [themeURL, readFileSync(path.join(repositoryRoot, "updates/themes.json"))],
    [themeURL + ".sig", readFileSync(path.join(repositoryRoot, "updates/themes.json.sig"))],
  ]);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const url = String(input);
    const body = fixtures.get(url);
    if (!body) return new Response("missing", { status: 404 });
    return {
      ok: true,
      status: 200,
      url,
      headers: new Headers({ "content-length": String(body.length) }),
      arrayBuffer: async () =>
        body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength),
    };
  };
  try {
    const result = await checkForUpdates(feedURL, "1.6.0");
    assert.equal(result.pass, true);
    assert.equal(result.updateAvailable, true);
    assert.equal(result.updateRequired, true);
    assert.equal(result.version, "1.6.1");
    assert.deepEqual(result.themes, []);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
