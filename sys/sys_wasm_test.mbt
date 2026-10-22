///|
test "wasm: file system" {
  // Removing files is unsupported on wasm, so the scratch directory is
  // reused across runs; `fs_roundtrip` only depends on what it writes.
  fs_roundtrip(scratch_dir("wasm"))
}

///|
test "wasm: unsupported operations" {
  let dir = scratch_dir("wasm")
  @sys.create_dir_all(dir)
  try @sys.remove_file(dir + "/a.txt") catch {
    e => {
      debug_inspect(e.kind(), content="Unsupported")
      inspect(e, content="operation not supported on this platform")
    }
  } noraise {
    _ => fail("expected Unsupported")
  }
  try @sys.symlink("a.txt", dir + "/link") catch {
    e => debug_inspect(e.kind(), content="Unsupported")
  } noraise {
    _ => fail("expected Unsupported")
  }
  try @sys.run_command("echo", []) catch {
    e => debug_inspect(e.kind(), content="Unsupported")
  } noraise {
    _ => fail("expected Unsupported")
  }
  assert_eq(@sys.hostname(), None)
  assert_false(@sys.is_tty(1))
  assert_false(@sys.stdin_is_readable())
}

///|
test "wasm: empty directory removal" {
  let dir = scratch_dir("wasm_rmdir")
  @sys.create_dir_all(dir + "/x/y")
  @sys.remove_dir_all(dir)
  assert_false(@sys.path_exists(dir))
}
