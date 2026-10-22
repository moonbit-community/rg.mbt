#!/bin/sh
# Runs ripgrep's own integration test suite (tests/*.rs in the ripgrep
# repository) against this port's `rg` binary.
#
# Usage: scripts/run_rg_integration_tests.sh [native|wasm] [test filter...]
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
exec "$testbin" "$@"
