#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
NODE="${NODE:-/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node}"
MAKENSIS="${MAKENSIS:-$(command -v makensis || true)}"
[ -x "$NODE" ] || { printf 'Node.js was not found: %s\n' "$NODE" >&2; exit 1; }
[ -n "$MAKENSIS" ] || { printf 'NSIS was not found. Install it with: brew install nsis\n' >&2; exit 1; }

while IFS= read -r -d '' script; do
  signature="$(/usr/bin/od -An -tx1 -N3 "$script" | /usr/bin/tr -d ' \n')"
  [ "$signature" = "efbbbf" ] || {
    printf 'Windows PowerShell 5.1 requires a UTF-8 BOM: %s\n' "$script" >&2
    exit 1
  }
done < <(/usr/bin/find "$ROOT/scripts" "$ROOT/tests" -type f -name '*.ps1' -print0)

RUNTIME_DIR="$ROOT/runtime"
RUNTIME_NODE="$RUNTIME_DIR/node.exe"
if [ ! -s "$RUNTIME_NODE" ]; then
  /bin/mkdir -p "$RUNTIME_DIR"
  NODE_VERSION="${WINDOWS_NODE_VERSION:-$(
    /usr/bin/curl -fsSL https://nodejs.org/dist/index.json |
      "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).find(x=>x.version.startsWith("v24.")).version))'
  )}"
  archive="/tmp/node-${NODE_VERSION}-win-x64.$$.zip"
  cleanup() { /bin/rm -f "$archive"; }
  trap cleanup EXIT
  /usr/bin/curl -fL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-win-x64.zip" -o "$archive"
  /usr/bin/unzip -p "$archive" "node-${NODE_VERSION}-win-x64/node.exe" > "$RUNTIME_NODE"
  [ -s "$RUNTIME_NODE" ] || { printf 'The bundled Windows Node.js runtime is empty.\n' >&2; exit 1; }
  trap - EXIT
  cleanup
fi

"$NODE" "$ROOT/scripts/generate-ico.mjs" >/dev/null
"$MAKENSIS" "$ROOT/installer/CodexDreamSkin.nsi"
OUTPUT="$ROOT/release/Codex-Skin-Manager-Setup-1.7.0.exe"
[ -s "$OUTPUT" ] || { printf 'NSIS did not create %s\n' "$OUTPUT" >&2; exit 1; }
/usr/bin/shasum -a 256 "$OUTPUT"
