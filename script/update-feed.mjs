#!/usr/bin/env node

import {
  createHash,
  createPrivateKey,
  createPublicKey,
  sign,
  verify,
} from "node:crypto";
import { execFile as execFileCallback } from "node:child_process";
import { readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath, pathToFileURL } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const updatesRoot = path.join(repositoryRoot, "updates");
const repository = "houyuhang915-sudo/Codex-Skin-Manager";
const execFile = promisify(execFileCallback);

export function compareVersions(left, right) {
  const parse = (value) => {
    const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(String(value));
    if (!match) throw new Error(`Invalid semantic version: ${value}`);
    return match.slice(1).map(Number);
  };
  const lhs = parse(left);
  const rhs = parse(right);
  for (let index = 0; index < 3; index += 1) {
    if (lhs[index] !== rhs[index]) return lhs[index] < rhs[index] ? -1 : 1;
  }
  return 0;
}

export function validateFeed(feed) {
  if (!feed || feed.schemaVersion !== 1 || feed.channel !== "stable") {
    throw new Error("Update feed must use stable schema 1.");
  }
  compareVersions(feed.version, feed.minimumVersion);
  if (!Number.isFinite(Date.parse(feed.publishedAt))) throw new Error("Invalid feed date.");
  if (!isHTTPS(feed.releaseNotesUrl)) throw new Error("Release notes URL must use HTTPS.");
  for (const platformName of ["macos", "windows"]) {
    validateAsset(feed.platforms?.[platformName], `${platformName} update`);
  }
  if (!isHTTPS(feed.themeCatalog?.url) || !isSHA256(feed.themeCatalog?.sha256)) {
    throw new Error("Theme catalog metadata is invalid.");
  }
  return feed;
}

export function validateCatalog(catalog) {
  if (!catalog || catalog.schemaVersion !== 1 ||
      !Number.isInteger(catalog.catalogVersion) || catalog.catalogVersion < 1 ||
      !Array.isArray(catalog.themes)) {
    throw new Error("Theme catalog must use schema 1 and a positive catalog version.");
  }
  const ids = new Set();
  for (const theme of catalog.themes) {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(theme.id) || ids.has(theme.id)) {
      throw new Error(`Invalid or duplicate theme id: ${theme.id}`);
    }
    ids.add(theme.id);
    if (!Number.isInteger(theme.version) || theme.version < 1) {
      throw new Error(`Invalid theme version: ${theme.id}`);
    }
    compareVersions(theme.minimumAppVersion, theme.minimumAppVersion);
    validateAsset(theme, `theme ${theme.id}`);
  }
  return catalog;
}

function validateAsset(asset, label) {
  if (!asset || !isHTTPS(asset.url) || !isSHA256(asset.sha256) ||
      !Number.isInteger(asset.size) || asset.size < 1 || asset.size > 536870912) {
    throw new Error(`${label} metadata is invalid.`);
  }
}

function isHTTPS(value) {
  try { return new URL(String(value)).protocol === "https:"; } catch { return false; }
}

function isSHA256(value) {
  return /^[a-f0-9]{64}$/.test(String(value));
}

async function sha256(file) {
  return createHash("sha256").update(await readFile(file)).digest("hex");
}

async function signFile(input, signature, privateKeyPath) {
  const privateJwk = JSON.parse(await readFile(privateKeyPath, "utf8"));
  const key = createPrivateKey({ key: privateJwk, format: "jwk" });
  const data = await readFile(input);
  await writeFile(signature, `${sign(null, data, key).toString("base64")}\n`);
}

async function verifyFile(input, signature, publicKeyPath) {
  const publicJwk = JSON.parse(await readFile(publicKeyPath, "utf8"));
  const key = createPublicKey({ key: publicJwk, format: "jwk" });
  const data = await readFile(input);
  const detached = Buffer.from((await readFile(signature, "utf8")).trim(), "base64");
  if (!verify(null, data, key, detached)) throw new Error(`Invalid signature: ${input}`);
}

function argument(name, required = true) {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  if (required && (!value || value.startsWith("--"))) throw new Error(`Missing ${name}`);
  return value;
}

async function generate() {
  const version = argument("--version");
  compareVersions(version, version);
  const macAsset = path.resolve(argument("--mac-asset"));
  const windowsAsset = path.resolve(argument("--windows-asset"));
  const privateKey = path.resolve(argument("--private-key"));
  const catalogPath = path.join(updatesRoot, "themes.json");
  const catalog = validateCatalog(JSON.parse(await readFile(catalogPath, "utf8")));
  catalog.publishedAt = new Date().toISOString();
  await writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
  await signFile(catalogPath, `${catalogPath}.sig`, privateKey);

  const [macStat, windowsStat] = await Promise.all([stat(macAsset), stat(windowsAsset)]);
  const releaseBase = `https://github.com/${repository}/releases/download/v${version}`;
  const feed = {
    schemaVersion: 1,
    channel: "stable",
    version,
    minimumVersion: "1.6.1",
    publishedAt: new Date().toISOString(),
    releaseNotesUrl: `https://github.com/${repository}/releases/tag/v${version}`,
    platforms: {
      macos: {
        url: `${releaseBase}/${path.basename(macAsset)}`,
        sha256: await sha256(macAsset),
        size: macStat.size,
      },
      windows: {
        url: `${releaseBase}/${path.basename(windowsAsset)}`,
        sha256: await sha256(windowsAsset),
        size: windowsStat.size,
      },
    },
    themeCatalog: {
      url: `https://raw.githubusercontent.com/${repository}/main/updates/themes.json`,
      sha256: await sha256(catalogPath),
    },
  };
  validateFeed(feed);
  const feedPath = path.join(updatesRoot, "stable.json");
  await writeFile(feedPath, `${JSON.stringify(feed, null, 2)}\n`);
  await signFile(feedPath, `${feedPath}.sig`, privateKey);
  process.stdout.write(`${feedPath}\n`);
}

async function addTheme() {
  const source = path.resolve(argument("--theme"));
  const themeVersion = Number(argument("--theme-version"));
  const minimumAppVersion = argument("--minimum-app");
  const downloadURL = argument("--url");
  const output = path.resolve(argument("--output"));
  const privateKey = path.resolve(argument("--private-key"));
  compareVersions(minimumAppVersion, minimumAppVersion);
  if (!Number.isInteger(themeVersion) || themeVersion < 1 || !isHTTPS(downloadURL)) {
    throw new Error("Theme version or download URL is invalid.");
  }
  const manifest = JSON.parse(await readFile(path.join(source, "theme.json"), "utf8"));
  if (manifest.schemaVersion !== 2 ||
      !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(manifest.id) ||
      !manifest.name ||
      manifest.image !== "background.png" ||
      manifest.preview !== "preview.png" ||
      manifest.avatarOverlay !== "show") {
    throw new Error("Theme package does not match the schema 2 online contract.");
  }
  for (const filename of ["theme.json", "background.png", "preview.png"]) {
    const info = await stat(path.join(source, filename));
    if (!info.isFile() || info.size < 1 || info.size > 31457280) {
      throw new Error("Theme file is invalid: " + filename);
    }
  }
  await rm(output, { force: true });
  await execFile("zip", ["-r", "-X", output, path.basename(source)], {
    cwd: path.dirname(source),
  });
  const archiveInfo = await stat(output);
  const entry = {
    id: manifest.id,
    name: manifest.name,
    version: themeVersion,
    minimumAppVersion,
    url: downloadURL,
    sha256: await sha256(output),
    size: archiveInfo.size,
    description: manifest.description || "",
  };

  const catalogPath = path.join(updatesRoot, "themes.json");
  const catalog = validateCatalog(JSON.parse(await readFile(catalogPath, "utf8")));
  catalog.catalogVersion += 1;
  catalog.publishedAt = new Date().toISOString();
  catalog.themes = catalog.themes.filter((theme) => theme.id !== entry.id);
  catalog.themes.push(entry);
  catalog.themes.sort((left, right) => left.id.localeCompare(right.id));
  validateCatalog(catalog);
  await writeFile(catalogPath, JSON.stringify(catalog, null, 2) + "\n");
  await signFile(catalogPath, catalogPath + ".sig", privateKey);

  const feedPath = path.join(updatesRoot, "stable.json");
  const feed = validateFeed(JSON.parse(await readFile(feedPath, "utf8")));
  feed.themeCatalog.sha256 = await sha256(catalogPath);
  await writeFile(feedPath, JSON.stringify(feed, null, 2) + "\n");
  await signFile(feedPath, feedPath + ".sig", privateKey);
  process.stdout.write(JSON.stringify(entry) + "\n");
}

async function validate() {
  const feedPath = path.join(updatesRoot, "stable.json");
  const catalogPath = path.join(updatesRoot, "themes.json");
  const publicKey = path.join(updatesRoot, "public-key.json");
  await verifyFile(feedPath, `${feedPath}.sig`, publicKey);
  await verifyFile(catalogPath, `${catalogPath}.sig`, publicKey);
  const feed = validateFeed(JSON.parse(await readFile(feedPath, "utf8")));
  validateCatalog(JSON.parse(await readFile(catalogPath, "utf8")));
  if (feed.themeCatalog.sha256 !== await sha256(catalogPath)) {
    throw new Error("Theme catalog SHA-256 does not match stable.json.");
  }
  process.stdout.write("PASS: signed update feed and theme catalog are valid.\n");
}

async function main() {
  switch (process.argv[2]) {
  case "add-theme": await addTheme(); break;
  case "generate": await generate(); break;
  case "sign":
    await signFile(
      path.resolve(argument("--input")),
      path.resolve(argument("--signature")),
      path.resolve(argument("--private-key")),
    );
    break;
  case "validate": await validate(); break;
  default: throw new Error("Usage: update-feed.mjs <add-theme|generate|sign|validate>");
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
