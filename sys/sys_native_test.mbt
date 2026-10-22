///|
test "native: file system" {
  let dir = scratch_dir("native")
  if @sys.path_exists(dir) {
    @sys.remove_dir_all(dir)
  }
  fs_roundtrip(dir)

  // Symlinks.
  @sys.create_dir_all(dir + "/links")
  @sys.symlink("../a.txt", dir + "/links/file")
  @sys.symlink("../sub", dir + "/links/dir")
  @sys.symlink("nope", dir + "/links/dangling")
  let entries = @sys.read_dir(dir + "/links")
  debug_inspect(
    names(entries),
    content=(
      #|["dangling", "dir", "file"]
    ),
  )
  for e in entries {
    assert_true(e.file_type is (Some(Symlink) | None))
  }
  assert_eq(@sys.read_link(dir + "/links/file"), "../a.txt")
  let lmd = @sys.symlink_metadata(dir + "/links/file")
  assert_eq(lmd.file_type, Symlink)
  assert_eq(lmd.len, 8L)
  let md = @sys.metadata(dir + "/links/file")
  assert_eq(md.file_type, File)
  assert_eq(md.len, 12L)
  assert_eq(md.ino, @sys.metadata(dir + "/a.txt").ino)
  assert_eq(md.dev, @sys.metadata(dir + "/a.txt").dev)
  assert_eq(@sys.metadata(dir + "/links/dir").file_type, Dir)
  assert_eq(@sys.symlink_metadata(dir + "/links/dangling").file_type, Symlink)
  try @sys.metadata(dir + "/links/dangling") catch {
    e => inspect(e, content="No such file or directory (os error 2)")
  } noraise {
    _ => fail("expected NotFound")
  }
  assert_eq(@sys.read_file(dir + "/links/file"), b"hello\nworld\n")

  // Removal.
  @sys.remove_file(dir + "/t.txt")
  assert_false(@sys.path_exists(dir + "/t.txt"))
  try @sys.remove_file(dir + "/t.txt") catch {
    e => debug_inspect(e.kind(), content="NotFound")
  } noraise {
    _ => fail("expected NotFound")
  }
  @sys.remove_dir_all(dir)
  assert_false(@sys.path_exists(dir))
}

///|
test "native: process info" {
  assert_true(@sys.now_nanos() > 0L)
  let t0 = @sys.now_nanos()
  assert_true(@sys.now_nanos() >= t0)
  assert_true(@sys.hostname() is Some(_))
  assert_true(@sys.env_var("PATH") is Some(_))
}

///|
test "native: run_command" {
  let out = @sys.run_command("sh", [
    "-c", "printf 'out\\n'; printf 'err\\n' >&2; exit 3",
  ])
  assert_eq(out.status, 3)
  assert_eq(out.stdout, b"out\n")
  assert_eq(out.stderr, b"err\n")
  // stdin defaults to /dev/null.
  let out = @sys.run_command("cat", [])
  assert_eq(out.status, 0)
  assert_eq(out.stdout, b"")
  // stdin from a file.
  let dir = scratch_dir("native_run")
  @sys.create_dir_all(dir)
  @sys.write_file(dir + "/in.txt", b"from file\n")
  let out = @sys.run_command("cat", [], stdin_path=dir + "/in.txt")
  assert_eq(out.stdout, b"from file\n")
  // Large output on both pipes must not deadlock.
  let out = @sys.run_command("sh", [
    "-c", "i=0; while [ $i -lt 2000 ]; do echo 0123456789012345678901234567890123456789; echo e0123456789012345678901234567890123456789 >&2; i=$((i+1)); done",
  ])
  assert_eq(out.stdout.length(), 2000 * 41)
  assert_eq(out.stderr.length(), 2000 * 42)
  // Killed by a signal.
  let out = @sys.run_command("sh", ["-c", "kill -9 $$"])
  assert_eq(out.status, 128 + 9)
  try @sys.run_command("rgsys-no-such-program", []) catch {
    e => inspect(e, content="No such file or directory (os error 2)")
  } noraise {
    _ => fail("expected NotFound")
  }
  @sys.remove_dir_all(dir)
}
