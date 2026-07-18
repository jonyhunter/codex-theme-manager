import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const template = await fs.readFile(path.join(root, "assets", "renderer-inject.js"), "utf8");
const css = await fs.readFile(path.join(root, "assets", "dream-skin.css"), "utf8");
const miku = JSON.parse(
  await fs.readFile(path.join(root, "themes", "miku-dream-skin", "theme.json"), "utf8"),
);

for (const placeholder of [
  "__DREAM_SKIN_CSS_JSON__",
  "__DREAM_SKIN_ART_JSON__",
  "__DREAM_SKIN_THEME_JSON__",
  "__DREAM_SKIN_VERSION_JSON__",
]) {
  assert.ok(template.includes(placeholder), `Renderer template is missing ${placeholder}.`);
}

assert.match(
  template,
  /THEME\.appearance === "light" \|\| THEME\.appearance === "dark"[\s\S]{0,100}\? THEME\.appearance[\s\S]{0,100}: detectShellMode\(\)/,
  "A theme's forced appearance must override the native app appearance.",
);
assert.match(
  template,
  /shell === "light" \? THEME\.colorsLight : THEME\.colorsDark/,
  "The renderer must select the shell-specific palette.",
);
assert.match(
  template,
  /dream-skin-settings-sidebar[\s\S]{0,600}dream-skin-settings-shell/,
  "Settings navigation and content surfaces must receive stable theme classes.",
);
assert.match(
  template,
  /dream-skin-library-page[\s\S]{0,500}dream-skin-library-search/,
  "The theme library and search surface must receive stable theme classes.",
);
assert.match(
  template,
  /cleanup = \(\) => \{[\s\S]{0,3500}URL\.revokeObjectURL\(state\.artUrl\)/,
  "Cleanup must remove injected state and release the artwork object URL.",
);
assert.match(
  css,
  /main\.main-surface:not\(\.dream-skin-home-shell\)[\s\S]{0,500}var\(--dream-skin-art\) 72% center \/ cover no-repeat/,
  "Chat and utility routes must use the same full-cover theme background.",
);
assert.match(
  css,
  /data-dream-shell="light"[\s\S]{0,2200}--color-token-text-primary:\s*var\(--ds-text\)/,
  "Light themes must remap native Codex text tokens to readable theme colors.",
);
assert.match(
  css,
  /data-dream-view="settings"/,
  "The stylesheet must include dedicated settings-page coverage.",
);
assert.doesNotMatch(
  css,
  /main\.main-surface\s*>\s*header\.app-header-tint\s*\{[^}]*\b(?:position|z-index)\s*:/,
  "Theme CSS must preserve the native fixed header and side-panel control.",
);
assert.equal(miku.appearance, "light", "The bundled Hatsune Miku theme must use its light palette.");
assert.equal(miku.avatarOverlay, "show", "Theme switches must preserve the pet overlay.");

console.log("PASS: renderer appearance, route backgrounds, settings, cleanup, and Miku light mode are covered.");
