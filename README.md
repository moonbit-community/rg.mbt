# rg.mbt — ripgrep ported to MoonBit

A port of [ripgrep](https://github.com/BurntSushi/ripgrep) (version 15.2.0)
to [MoonBit](https://www.moonbitlang.com/). The goal is behavioral fidelity:
the same flags, output format, error messages and exit codes as `rg`.

It builds for two backends:

- **native** (the default): uses a small C stub for OS access.
- **wasm** (linear-memory WebAssembly): uses a subset of WASI preview 1 that
  is supported by both `wasmtime` and MoonBit's own `moonrun`.

## Building and running

```sh
# native
moon build --release cmd/rg
_build/native/release/build/cmd/rg/rg.exe --help

# wasm, via moon's runner (paths are relative to the current directory)
moon run --target wasm cmd/rg -- PATTERN some/dir

# wasm, via wasmtime (preopen the directories you want to search)
moon build --release --target wasm cmd/rg
wasmtime run --dir . _build/wasm/release/build/cmd/rg/rg.wasm PATTERN .
```

## Layout

Each ripgrep crate maps to a MoonBit package:

| ripgrep crate | package | notes |
|---|---|---|
| `regex-syntax` | `regex/syntax`, `regex/unicode` | parser, HIR, Unicode tables, literal extraction |
| `regex-automata` | `regex/automata`, `regex` | Thompson NFA, PikeVM, lazy DFA, prefilters, meta regex |
| `grep-matcher` | `matcher` | the `Matcher` trait |
| `grep-regex` | `grep_regex` | `RegexMatcher` |
| `grep-searcher` | `searcher` | line-oriented searching, binary detection, transcoding |
| `grep-printer` | `printer`, `termcolor` | standard, summary and JSON output |
| `globset` | `globset` | |
| `ignore` | `ignore` | gitignore, file types, overrides, directory walking |
| `grep-cli` | `cli` | |
| `ripgrep` (core) | `core`, `cmd/rg` | flags, help/man/completions, search driver |
| (std) | `sys` | OS abstraction for native and WASI |

The regex engine is written from scratch in MoonBit following the design of
Rust's `regex-syntax`/`regex-automata` (leftmost-first semantics, byte
oriented, Unicode aware), and is tested against the `regex` crate's TOML test
corpus (`regex/internal/testdata`).

## Testing

```sh
moon test                 # native
moon test --target wasm   # wasm
```

ripgrep's own integration suite (`tests/*.rs` in the ripgrep repository,
323 tests) can be run against this port. It needs a ripgrep checkout in
`.repos/ripgrep` and a Rust toolchain that can build it:

```sh
scripts/run_rg_integration_tests.sh native   # 323/323 pass
scripts/run_rg_integration_tests.sh wasm     # 305/323 pass (wasmtime)
```

The 18 wasm failures are all due to WASI rather than the port: 9 need to
spawn a process (`-z/--search-zip`, `--pre`), 3 rely on stdin being detected
as readable when no path is given, and 6 search symlinks with absolute
targets, which wasmtime's sandbox refuses to read.

## Differences from ripgrep

- No PCRE2 (`--pcre2` reports that PCRE2 is unavailable, like a build of
  ripgrep without the `pcre2` feature).
- Searching is single threaded (`-j/--threads` is accepted; output is the
  same as `rg -j1`).
- No memory maps; files are always read incrementally.
- On wasm:
  - No subprocesses: `--pre` reports that the preprocessor could not start,
    and `-z/--search-zip` searches compressed files as-is (as ripgrep does
    when the decompression tool isn't installed).
  - No file timestamps: `--sort modified` etc. report that sorting isn't
    supported.
  - Stdin is only searched when `-` is given explicitly (ripgrep built for
    WASI behaves the same way, since the type of stdin can't be queried).
  - Only preopened directories are reachable. `wasmtime run --dir . --dir /`
    gives full access (except to symlinks with absolute targets); `moonrun`
    only exposes the current directory, so ignore files in parent
    directories and absolute paths outside it are not visible.
