#!/usr/bin/env node

import { createHash, createPublicKey, verify } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, readFile, rename, rm, stat } from "node:fs/promises";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { pathToFileURL } from "node:url";

export const CURRENT_VERSION = "1.7.2";
export const DEFAULT_FEED_URL =
  "https://raw.githubusercontent.com/houyuhang915-sudo/Codex-Skin-Manager/main/updates/stable.json";
export const UPDATE_PUBLIC_KEY = {
  kty: "OKP",
  crv: "Ed25519",
  x: "5_BSHZg9M_SVnRiUlMqF24Am-kprwLXYgDljQcFNOKc",
};

const maximumAssetBytes = 536870912;

export function compareVersions(left, right) {
  const parse = (value) => {
    const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(String(value));
    if (!match) throw new Error(`版本号格式无效：${value}`);
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
    throw new Error("更新清单格式不受支持。");
  }
  compareVersions(feed.version, feed.minimumVersion);
  if (!Number.isFinite(Date.parse(feed.publishedAt))) throw new Error("更新发布日期无效。");
  validateHTTPS(feed.releaseNotesUrl, "版本说明");
  for (const platform of ["macos", "windows"]) validateAsset(feed.platforms?.[platform]);
  validateHTTPS(feed.themeCatalog?.url, "主题目录");
  validateSHA256(feed.themeCatalog?.sha256);
  return feed;
}

export function validateCatalog(catalog) {
  if (!catalog || catalog.schemaVersion !== 1 ||
      !Number.isInteger(catalog.catalogVersion) || catalog.catalogVersion < 1 ||
      !Array.isArray(catalog.themes)) {
    throw new Error("在线主题目录格式不受支持。");
  }
  const ids = new Set();
  for (const theme of catalog.themes) {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(theme.id) || ids.has(theme.id)) {
      throw new Error(`在线主题 ID 无效或重复：${theme.id}`);
    }
    ids.add(theme.id);
    if (!Number.isInteger(theme.version) || theme.version < 1) {
      throw new Error(`在线主题版本无效：${theme.id}`);
    }
    compareVersions(theme.minimumAppVersion, theme.minimumAppVersion);
    validateAsset(theme);
  }
  return catalog;
}

function validateAsset(asset) {
  if (!asset || !Number.isInteger(asset.size) || asset.size < 1 || asset.size > maximumAssetBytes) {
    throw new Error("更新文件大小无效。");
  }
  validateHTTPS(asset.url, "更新文件");
  validateSHA256(asset.sha256);
}

function validateHTTPS(value, label) {
  let url;
  try { url = new URL(String(value)); } catch { throw new Error(`${label}地址无效。`); }
  const allowLocalHTTP = process.env.CODEX_UPDATE_ALLOW_HTTP === "1" &&
    ["127.0.0.1", "localhost"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && allowLocalHTTP)) {
    throw new Error(`${label}必须使用 HTTPS。`);
  }
}

function validateSHA256(value) {
  if (!/^[a-f0-9]{64}$/.test(String(value))) throw new Error("SHA-256 格式无效。");
}

function signatureURL(url) {
  return new URL(`${url.toString()}.sig`);
}

async function fetchBytes(url, expectedMaximum = 2 * 1024 * 1024) {
  validateHTTPS(url, "下载");
  const response = await fetch(url, {
    redirect: "follow",
    signal: AbortSignal.timeout(20000),
    headers: { "User-Agent": `Codex-Skin-Manager/${CURRENT_VERSION}` },
  });
  if (!response.ok) throw new Error(`下载失败：HTTP ${response.status}`);
  validateHTTPS(response.url, "下载重定向");
  const contentLength = Number(response.headers.get("content-length") || 0);
  if (contentLength > expectedMaximum) throw new Error("下载内容超过大小限制。");
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 1 || bytes.length > expectedMaximum) throw new Error("下载内容大小无效。");
  return bytes;
}

export async function fetchSignedJSON(url, expectedMaximum = 2 * 1024 * 1024) {
  const parsedURL = new URL(url);
  const [data, signatureData] = await Promise.all([
    fetchBytes(parsedURL, expectedMaximum),
    fetchBytes(signatureURL(parsedURL), 4096),
  ]);
  const signature = Buffer.from(signatureData.toString("utf8").trim(), "base64");
  const publicKey = createPublicKey({ key: UPDATE_PUBLIC_KEY, format: "jwk" });
  if (signature.length !== 64 || !verify(null, data, publicKey, signature)) {
    throw new Error("更新清单签名校验失败。");
  }
  return { data, value: JSON.parse(data.toString("utf8")) };
}

export async function checkForUpdates(feedURL, currentVersion) {
  const signedFeed = await fetchSignedJSON(feedURL);
  const feed = validateFeed(signedFeed.value);
  const signedCatalog = await fetchSignedJSON(feed.themeCatalog.url);
  const catalogHash = createHash("sha256").update(signedCatalog.data).digest("hex");
  if (catalogHash !== feed.themeCatalog.sha256) throw new Error("在线主题目录摘要校验失败。");
  const catalog = validateCatalog(signedCatalog.value);
  return {
    pass: true,
    currentVersion,
    updateAvailable: compareVersions(feed.version, currentVersion) > 0,
    updateRequired: compareVersions(currentVersion, feed.minimumVersion) < 0,
    version: feed.version,
    releaseNotesUrl: feed.releaseNotesUrl,
    platform: feed.platforms.windows,
    catalogVersion: catalog.catalogVersion,
    themes: catalog.themes.filter((theme) =>
      compareVersions(currentVersion, theme.minimumAppVersion) >= 0),
  };
}

async function fileSHA256(file) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}

async function downloadAsset(url, output, expectedHash, expectedSize) {
  validateHTTPS(url, "更新文件");
  validateSHA256(expectedHash);
  if (!Number.isInteger(expectedSize) || expectedSize < 1 || expectedSize > maximumAssetBytes) {
    throw new Error("更新文件大小无效。");
  }
  await mkdir(path.dirname(output), { recursive: true });
  const temporary = `${output}.downloading.${process.pid}`;
  await rm(temporary, { force: true });
  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: AbortSignal.timeout(900000),
      headers: { "User-Agent": `Codex-Skin-Manager/${CURRENT_VERSION}` },
    });
    if (!response.ok || !response.body) throw new Error(`下载失败：HTTP ${response.status}`);
    validateHTTPS(response.url, "更新文件重定向");
    const contentLength = Number(response.headers.get("content-length") || 0);
    if (contentLength && contentLength !== expectedSize) throw new Error("更新文件大小与清单不一致。");
    await pipeline(Readable.fromWeb(response.body), createWriteStream(temporary, { flags: "wx" }));
    if ((await stat(temporary)).size !== expectedSize) throw new Error("更新文件下载不完整。");
    if (await fileSHA256(temporary) !== expectedHash) throw new Error("更新文件 SHA-256 校验失败。");
    await rm(output, { force: true });
    await rename(temporary, output);
    return { pass: true, output, size: expectedSize, sha256: expectedHash };
  } finally {
    await rm(temporary, { force: true });
  }
}

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const command = process.argv[2];
  if (command === "check") {
    const result = await checkForUpdates(
      argument("--feed", process.env.CODEX_UPDATE_FEED_URL || DEFAULT_FEED_URL),
      argument("--current", CURRENT_VERSION),
    );
    process.stdout.write(`${JSON.stringify(result)}\n`);
    return;
  }
  if (command === "download") {
    const result = await downloadAsset(
      argument("--url"),
      path.resolve(argument("--output")),
      argument("--sha256"),
      Number(argument("--size")),
    );
    process.stdout.write(`${JSON.stringify(result)}\n`);
    return;
  }
  throw new Error("Usage: update-client.mjs <check|download>");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
