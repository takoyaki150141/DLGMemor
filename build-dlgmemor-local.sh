#!/usr/bin/env bash
# build-dlgmemor-local.sh — one-shot build script for DLGMemor on your Mac.
# Tested against theos clang (iOS 16.0 SDK, Xcode 15.4).
#
# Usage:
#   cd ~/DLGMemor
#   git fetch origin && git checkout feat/ios26-port
#   ./build-dlgmemor-local.sh
#
# Output: ./build_output/DLGMemor.dylib  (drop into LiveContainer)
set -euo pipefail

# --- 0. Sanity ---
if [[ "$(uname)" != "Darwin" ]]; then
  echo "[error] must run on macOS (you are on $(uname))" >&2
  exit 1
fi

if [[ -z "${THEOS:-}" ]]; then
  if [[ -d "$HOME/theos" ]]; then
    export THEOS="$HOME/theos"
  else
    echo "[error] \$THEOS not set and ~/theos not found" >&2
    exit 1
  fi
fi

# Stub ldid if real one isn't installed.
if ! command -v ldid >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/ldid" <<'STUB'
#!/bin/bash
for arg in "$@"; do echo "[stub ldid] $arg" >&2; done
exit 0
STUB
  chmod +x "$HOME/.local/bin/ldid"
fi
export PATH="$HOME/.local/bin:$PATH"

echo "[+] THEOS = $THEOS"
echo "[+] ldid  = $(command -v ldid)"

# --- 1. Clean & build ---
make clean
make all FINALPACKAGE=1

# --- 2. Collect ---
mkdir -p build_output
DYLIB="$(find .theos/obj/ -name DLGMemor.dylib -print -quit)"
if [[ -z "$DYLIB" ]]; then
  echo "[error] DLGMemor.dylib not produced" >&2
  exit 1
fi
cp "$DYLIB" build_output/DLGMemor.dylib

echo ""
echo "[+] build_output/"
ls -la build_output/
echo ""
echo "[+] Verify it's a fat dylib:"
file build_output/DLGMemor.dylib
lipo -info build_output/DLGMemor.dylib || true
echo ""
echo "[+] Drop build_output/DLGMemor.dylib into LiveContainer's Documents/inject."