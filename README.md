# rg.mbt — ripgrep ported to MoonBit

A port of [ripgrep](https://github.com/BurntSushi/ripgrep) (version 15.2.0)
to [MoonBit](https://www.moonbitlang.com/). The goal is behavioral fidelity:
the same flags, output format, error messages and exit codes as `rg`.

It builds for two backends:

- **native** (the default): uses a small C stub for OS access.
- **wasm** (linear-memory WebAssembly): uses a subset of WASI preview 1 that
  is supported by both `wasmtime` and MoonBit's own `moonrun`.

## Installing

The module is published on [mooncakes.io](https://mooncakes.io) as
`moonbit-community/rg`. To build the `rg` binary from source:

```sh
git clone https://github.com/moonbit-community/rg.mbt
cd rg.mbt
moon build --release cmd/rg
```

## Building and running

```sh
# native
moon build --release cmd/rg
_build/native/release/build/cmd/rg/rg.exe --help

# wasm, via moon's runner (paths are relative to the current directory)
moon run --target wasm cmd/rg -- PATTERN some/dir

# wasm, via wasmtime (preopen the directories you want to search); the
# script builds and optimizes the module (see "Performance")
scripts/build_wasm.sh
wasmtime run --dir . _build/wasm/release/build/cmd/rg/rg.opt.wasm PATTERN .
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

ripgrep's own integration suite (`tests/*.rs` in the ripgrep repository)
can be run against this port. It needs a ripgrep checkout in `.repos/ripgrep`
(CI uses revision `3fce3b5bb0`) and a Rust toolchain that can build it:

```sh
scripts/run_rg_integration_tests.sh native
scripts/run_rg_integration_tests.sh wasm     # needs wasmtime
```

| platform | tests | native | wasm (wasmtime) |
|---|---|---|---|
| Linux | 332 | all pass | 306 pass, 26 skipped |
| macOS | 323 | all pass | 302 pass, 21 skipped |

The tests skipped on wasm can't pass under WASI, and they would fail for
ripgrep built for WASI too. They need to spawn processes (`-z/--search-zip`,
`--pre`), detect stdin as readable when no path is given, follow symlinks with
absolute targets (refused by wasmtime's sandbox), use memory maps, or use file
names that aren't valid UTF-8. CI runs both suites on Linux.

## Performance

The hot paths (`memchr`, substring search, and Teddy for multiple
literals) are vectorized in pure MoonBit with `moonbitlang/core/v128`, which
lowers to NEON/SSE on native and to wasm SIMD on wasm. Like Rust's `memchr`,
they test 32–64 bytes per step with a cheap "any match" check, and the
search loops avoid allocating per line or per match.

Time relative to ripgrep 15.2.0 (hyperfine, 170 MB text file, Apple M2 Ultra;
ripgrep's `-j1 --no-mmap` is the same speed on a single file):

| search | native | wasm (wasmtime) | wasm (moonrun / V8) |
|---|---|---|---|
| rare literal / no match | 1.0x | 2.1x | 2.8–2.9x |
| case-insensitive literal (`-i`) | 1.1x | 1.9x | 2.1x |
| alternation of literals | 1.0x | 1.8x | 2.2x |
| regex with a literal suffix (`[A-Z][a-z]+Error`) | 1.1x | 2.4x | 2.9x |
| regex dominated by the DFA (`\w+_\w+\(`) | 0.9x | 1.9x | 1.9x |
| Unicode class (`\p{Greek}`) | 1.0x | 2.5x | 3.0x |
| many matches (`-c self`, `-n self`, `-w`, `-o`) | 1.2–1.3x | 2.6–3.0x | 2.7–3.2x |
| `-v` (every other line through the sink) | 1.3x | 2.5x | 2.7x |
| `-C2` (context lines) | 1.6x | 3.8x | 3.6x |

The wasm numbers are for the module optimized by `scripts/build_wasm.sh`.
MoonBit's wasm output calls small runtime functions for reference counting
and bounds checks; inlining them with binaryen's `wasm-opt -O3 -aimfs=20`
(bundled with the toolchain as `moon-wasm-opt`) makes wasm searches up to
~40% faster (e.g. `-C2` under wasmtime went from 5.1x to 3.8x) for a ~20%
larger module. Modules run with `moonx` come from mooncakes.io and aren't
post-processed this way.

With the optimized module the two runners are close; wasmtime is usually
slightly faster, partly because it starts about 5 ms sooner.

Searching a directory tree is at parity with `rg -j1`; ripgrep's default
parallel search is faster on trees.

## Differences from ripgrep

- No PCRE2 (`--pcre2` reports that PCRE2 is unavailable, like a build of
  ripgrep without the `pcre2` feature).
- Searching is single threaded (`-j/--threads` is accepted; output is the
  same as `rg -j1`, including the single-threaded walker's error messages,
  e.g. `IO error for operation on <dir>: ...` for unreadable directories).
- No memory maps. Where ripgrep would use one (on Linux, when searching a
  few files given explicitly, or with `--mmap`), the whole file is read and
  searched as a slice instead, which gives the same output.
- Where ripgrep 15.2.0 panics, the port does something sensible instead:
  `--help`/`--version` in a config file are ignored, and JSON submatches of
  a multi-line match truncated by `-m` are clipped to the reported lines.
- `--regex-size-limit` uses regex-automata's accounting of NFA size, so the
  smallest accepted limit is the same as ripgrep's for most patterns; for
  patterns with large Unicode classes it can be slightly lower (by a few
  percent).
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
