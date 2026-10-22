#!/bin/sh
# Runs ripgrep's own integration test suite (tests/*.rs in the ripgrep
# repository) against this port's `rg` binary.
#
# Usage: scripts/run_rg_integration_tests.sh [native|wasm] [test filter...]
#
# On wasm, the tests that cannot pass under WASI are skipped unless test
# filters are given (or RG_NO_SKIP=1). On all platforms: 10 need to spawn
# processes (decompression, --pre), 3 rely on stdin being detected as
# readable when no path is given, and 5 search symlinks with absolute
# targets, which wasmtime's sandbox refuses to read. Linux-only tests: 1 more
# needs a process, 5 expect memory maps (which WASI doesn't have), and 2 use
# file names that aren't valid UTF-8 (which WASI can't represent).
#
# Requires a ripgrep checkout in .repos/ripgrep and a Rust toolchain that can
# build it (ripgrep 15.2 needs rustc >= 1.96; override with RG_TOOLCHAIN).
set -e
cd "$(dirname "$0")/.."
root=$(pwd)
target=${1:-native}
[ $# -gt 0 ] && shift
toolchain=${RG_TOOLCHAIN:-+1.97.1}
tdir=${RG_TEST_TARGET_DIR:-$root/_build/rg-integration}

(cd .repos/ripgrep && cargo $toolchain test --release --no-run --test integration \
  --target-dir "$tdir" >/dev/null 2>&1) || {
  echo "failed to build ripgrep's integration tests" >&2
  exit 1
}
testbin=$(ls -t "$tdir"/release/deps/integration-* | grep -v '\.d$' | head -1)

case "$target" in
  native)
    moon build --release --target native cmd/rg >/dev/null
    export CARGO_BIN_EXE_rg="$root/_build/native/release/build/cmd/rg/rg.exe"
    ;;
  wasm)
    command -v wasmtime >/dev/null || {
      echo "wasmtime is required to run the wasm integration tests" >&2
      exit 1
    }
    moon build --release --target wasm cmd/rg >/dev/null
    export CARGO_BIN_EXE_rg="$root/_build/wasm/release/build/cmd/rg/rg.wasm"
    # The test harness runs the binary through `qemu-<arch>` whenever
    # CROSS_RUNNER is set (see cross_runner in tests/util.rs), so provide a
    # shim with that name that runs the module under wasmtime instead.
    bindir="$tdir/wasm-runner-bin"
    mkdir -p "$bindir"
    arch=$(uname -m)
    [ "$arch" = arm64 ] && arch=aarch64
    cat > "$bindir/qemu-$arch" <<'EOS'
#!/bin/sh
exec wasmtime run -S inherit-env=y --dir . --dir /::/ "$@"
EOS
    chmod +x "$bindir/qemu-$arch"
    export PATH="$bindir:$PATH"
    export CROSS_RUNNER=wasmtime
    ;;
  *)
    echo "unknown target: $target" >&2
    exit 1
    ;;
esac
if [ "$target" = wasm ] && [ $# -eq 0 ] && [ -z "$RG_NO_SKIP" ]; then
  for t in \
    misc::compressed_brotli misc::compressed_bzip2 misc::compressed_failing_gzip \
    misc::compressed_gzip misc::compressed_lz4 misc::compressed_lzma \
    misc::compressed_xz misc::compressed_zstd \
    misc::preprocessing misc::preprocessing_glob \
    binary::after_match1_stdin multiline::stdin \
    regression::r1223_no_dir_check_for_default_path \
    misc::symlink_follow regression::r137 regression::r256 regression::r256_j1 \
    regression::r1389_bad_symlinks_no_biscuit \
    misc::compressed_uncompress \
    binary::mmap_after_nul_match binary::mmap_binary_flag \
    binary::mmap_match_explicit binary::mmap_match_implicit \
    binary::mmap_match_multiple \
    regression::r210 json::notutf8; do
    set -- "$@" --skip "$t"
  done
  set -- "$@" --exact
fi
exec "$testbin" "$@"
