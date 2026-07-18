import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const repositoryRoot = path.resolve(windowsRoot, "..");

const [windowsTemplate, macosTemplate, windowsCss, macosCss, windowsMiku, macosMiku] =
  await Promise.all([
    fs.readFile(path.join(windowsRoot, "assets", "renderer-inject.js"), "utf8"),
    fs.readFile(path.join(repositoryRoot, "macos", "assets", "renderer-inject.js"), "utf8"),
    fs.readFile(path.join(windowsRoot, "assets", "dream-skin.css"), "utf8"),
    fs.readFile(path.join(repositoryRoot, "macos", "assets", "dream-skin.css"), "utf8"),
    fs.readFile(path.join(windowsRoot, "themes", "miku-dream-skin", "theme.json"), "utf8"),
    fs.readFile(
      path.join(repositoryRoot, "macos", "themes", "miku-dream-skin", "theme.json"),
      "utf8",
    ),
  ]);

assert.equal(
  windowsTemplate,
  macosTemplate,
  "Windows and macOS must ship the same renderer behavior.",
);
assert.equal(windowsCss, macosCss, "Windows and macOS must ship the same theme stylesheet.");
assert.equal(windowsMiku, macosMiku, "Bundled Miku manifests must remain identical across platforms.");

assert.match(
  windowsTemplate,
  /THEME\.appearance === "light" \|\| THEME\.appearance === "dark"/,
  "The Windows renderer must honor a theme's forced appearance.",
);
assert.match(
  windowsTemplate,
  /dream-skin-settings-sidebar[\s\S]{0,600}dream-skin-settings-shell/,
  "The Windows renderer must style settings navigation and content.",
);
assert.match(
  windowsCss,
  /data-dream-shell="light"[\s\S]{0,2200}--color-token-text-primary:\s*var\(--ds-text\)/,
  "Windows light themes must remap native Codex text tokens.",
);
assert.match(
  windowsCss,
  /main\.main-surface:not\(\.dream-skin-home-shell\)[\s\S]{0,500}var\(--dream-skin-art\) 72% center \/ cover no-repeat/,
  "Windows chat and utility routes must keep the full-cover background.",
);

console.log("PASS: Windows renderer and theme resources match the verified macOS implementation.");
