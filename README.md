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

The 18 tests that fail on wasm are all due to WASI rather than the port, and
the script skips them: 10 need to spawn a process (`-z/--search-zip`,
`--pre`), 3 rely on stdin being detected as readable when no path is given,
and 5 search symlinks with absolute targets, which wasmtime's sandbox refuses
to read.

## Performance

The hot paths (`memchr`, substring search, and Teddy for multiple
literals) are vectorized in pure MoonBit with `moonbitlang/core/v128`, which
lowers to NEON/SSE on native and to wasm SIMD on wasm.

Time relative to ripgrep 15.2.0 (hyperfine, 170 MB text file, Apple M2 Ultra;
ripgrep's `-j1 --no-mmap` is the same speed on a single file):

| search | native | wasm (wasmtime) | wasm (moonrun / V8) |
|---|---|---|---|
| rare literal / no match | 1.3x | 2.7x | 3.5x |
| case-insensitive literal (`-i`) | 1.3x | 2.6x | 2.6x |
| alternation of literals | 1.3x | 2.4x | 2.6x |
| regex with a literal suffix (`[A-Z][a-z]+Error`) | 1.4x | 3.2x | 3.5x |
| regex dominated by the DFA (`\w+_\w+\(`) | 1.0x | 2.7x | 2.0x |
| Unicode class (`\p{Greek}`) | 1.0x | 4.2x | 2.6x |
| printing many matching lines (`-n`) | 1.4x | 4.1x | 3.6x |
| `-v` / `-C2` (many lines through the sink) | 1.7–1.8x | 5–6x | 4.5–4.9x |

V8 is faster on compute-heavy searches; wasmtime starts about 5 ms faster,
which dominates short searches.

Searching a directory tree is at parity with `rg -j1`; ripgrep's default
parallel search is faster on trees. On wasm, MoonBit currently emits bounds
checks and reference counting as out-of-line runtime calls, which accounts
for most of the remaining gap to native.

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
