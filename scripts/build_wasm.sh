#!/bin/sh
# Builds `rg` for the linear-memory wasm backend and optimizes it with
# binaryen's wasm-opt (bundled with the MoonBit toolchain as moon-wasm-opt).
#
# MoonBit's wasm output calls small runtime helpers for reference counting
# and bounds checks; inlining them (-aimfs=20) makes searches up to ~40%
# faster under wasmtime and moonrun, at the cost of a ~20% larger module.
#
# Usage: scripts/build_wasm.sh   (prints the path of the optimized module)
set -e
cd "$(dirname "$0")/.."
moon build --release --target wasm cmd/rg >/dev/null
dir=_build/wasm/release/build/cmd/rg
opt=$(command -v moon-wasm-opt || command -v wasm-opt || true)
if [ -z "$opt" ]; then
  echo "neither moon-wasm-opt nor wasm-opt was found" >&2
  exit 1
fi
"$opt" --all-features -O3 -aimfs=20 "$dir/rg.wasm" -o "$dir/rg.opt.wasm"
echo "$dir/rg.opt.wasm"
