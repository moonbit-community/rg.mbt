# moonbit-community/rg/sys

Operating-system abstraction layer for the ripgrep port: arguments,
environment, raw stdio, files, directories, metadata and (native only)
subprocesses. Errors are `IOError`s that render like Rust's `io::Error`
(`No such file or directory (os error 2)`), always using Linux errno numbers
and `strerror` texts, whatever the host.

Supported backends: `native` (C stub, macOS and Linux) and `wasm` (linear
memory backend, WASI preview1). Other backends are not supported.

## Using it from a wasm executable

The executable package must export its linear memory as `memory`:

```
options(
  "is-main": true,
  link: { "wasm": { "export-memory-name": "memory" } },
)
```

The wasm build imports only the WASI functions that both `wasmtime` and
moonrun (`moon run --target wasm`, `moon test --target wasm`) implement, so a
single binary runs under both:

```
moon run --target wasm sys/internal/demo -- ls sys
wasmtime run --dir . _build/wasm/debug/build/sys/internal/demo/demo.wasm ls sys
```

Paths are resolved against the preopened directories: an absolute path uses
the preopen with the longest matching name (`--dir /host/path::/guest/path`),
a relative path uses the `.` preopen (`--dir .`; moonrun always preopens the
current directory as `.`), and as a fallback paths are resolved through
`$PWD`. Paths outside every preopen fail with
`failed to find a pre-opened file descriptor through which "..." could be opened`.

### Limitations on wasm

- `remove_file`, `symlink` and `run_command` raise `Unsupported`
  (`remove_dir_all` therefore only works on trees of empty directories).
- `metadata` cannot see `dev`/`ino` (always `0`), reports every
  non-directory as `File`, and computes `len` by reading the file.
- `is_tty` and `stdin_is_readable` are always `false`, `now_nanos` is `0`,
  `hostname` is `None`, and `current_dir` is `$PWD` or `"."` (wasmtime only
  passes environment variables given with `--env` or `-S inherit-env`).
