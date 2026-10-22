// Tests shared by all backends. Each backend calls `fs_roundtrip` with its
// own scratch directory (see `sys_native_test.mbt` / `sys_wasm_test.mbt`);
// the scratch root is `$RGSYS_TEST_DIR` or `_build/sys_test_tmp` relative to
// the current directory (the module root under `moon test`).

///|
fn scratch_dir(name : String) -> String {
  let root = match @sys.env_var("RGSYS_TEST_DIR") {
    Some(d) if d != "" => d
    _ => "_build/sys_test_tmp"
  }
  root + "/" + name
}

///|
fn names(entries : Array[@sys.DirEntry]) -> Array[String] {
  let ns = entries.map(e => e.name)
  // `String::compare` is not lexicographic; compare code units instead.
  ns.sort_by((a, b) => {
    for i in 0..<@cmp.minimum(a.length(), b.length()) {
      if a[i] != b[i] {
        return a[i].to_int() - b[i].to_int()
      }
    }
    a.length() - b.length()
  })
  ns
}

///|
fn type_of(entries : Array[@sys.DirEntry], name : String) -> @sys.FileType? {
  for e in entries {
    if e.name == name {
      return e.file_type
    }
  }
  None
}

///|
/// Exercises the file system API inside `dir` (which is created).
fn fs_roundtrip(dir : String) -> Unit raise {
  @sys.create_dir_all(dir + "/sub/deeper")
  // create_dir_all on an existing directory is a no-op.
  @sys.create_dir_all(dir + "/sub")
  @sys.write_file(dir + "/a.txt", b"hello\nworld\n")
  @sys.write_file(dir + "/sub/b.txt", b"")
  @sys.write_file(dir + "/sub/deeper/c.txt", b"c")
  // Truncation.
  @sys.write_file(dir + "/t.txt", b"long contents")
  @sys.write_file(dir + "/t.txt", b"short")
  assert_eq(@sys.read_file(dir + "/t.txt"), b"short")
  assert_eq(@sys.read_file(dir + "/a.txt"), b"hello\nworld\n")
  assert_eq(@sys.read_file(dir + "/sub/b.txt"), b"")

  // Chunked reads through File.
  let f = @sys.File::open(dir + "/a.txt")
  let buf : FixedArray[Byte] = FixedArray::make(16, 0)
  assert_eq(f.read(buf, 2, 5), 5)
  assert_eq(buf[2:7].to_owned(), [b'h', b'e', b'l', b'l', b'o'])
  assert_eq(f.read(buf, 0, 16), 7)
  assert_eq(f.read(buf, 0, 16), 0)
  f.close()
  f.close()

  // Directory listing.
  let entries = @sys.read_dir(dir)
  debug_inspect(
    names(entries).filter(n => n != "links"),
    content=(
      #|["a.txt", "sub", "t.txt"]
    ),
  )
  assert_true(type_of(entries, "a.txt") is (Some(File) | None))
  assert_true(type_of(entries, "sub") is (Some(Dir) | None))
  debug_inspect(
    names(@sys.read_dir(dir + "/sub")),
    content=(
      #|["b.txt", "deeper"]
    ),
  )

  // Metadata.
  let md = @sys.metadata(dir + "/a.txt")
  assert_eq(md.file_type, File)
  assert_eq(@sys.file_len(dir + "/a.txt"), 12L)
  assert_true(md.is_file())
  assert_eq(@sys.metadata(dir + "/sub").file_type, Dir)
  assert_eq(@sys.symlink_metadata(dir + "/sub").file_type, Dir)
  assert_eq(@sys.symlink_metadata(dir + "/a.txt").file_type, File)
  assert_eq(@sys.file_len(dir + "/./sub/../a.txt"), 12L)
  assert_true(@sys.path_exists(dir + "/sub/deeper/c.txt"))
  assert_false(@sys.path_exists(dir + "/nope"))

  // Errors.
  try @sys.read_file(dir + "/missing.txt") catch {
    e => {
      inspect(e, content="No such file or directory (os error 2)")
      debug_inspect(e.kind(), content="NotFound")
      assert_eq(e.code(), 2)
    }
  } noraise {
    _ => fail("expected NotFound")
  }
  try @sys.metadata(dir + "/missing") catch {
    e => inspect(e, content="No such file or directory (os error 2)")
  } noraise {
    _ => fail("expected NotFound")
  }
  try @sys.read_dir(dir + "/a.txt") catch {
    e => {
      inspect(e, content="Not a directory (os error 20)")
      debug_inspect(e.kind(), content="NotADirectory")
    }
  } noraise {
    _ => fail("expected NotADirectory")
  }
  try @sys.write_file(dir + "/missing/x.txt", b"") catch {
    e => debug_inspect(e.kind(), content="NotFound")
  } noraise {
    _ => fail("expected NotFound")
  }
  try @sys.read_link(dir + "/a.txt") catch {
    e => inspect(e, content="Invalid argument (os error 22)")
  } noraise {
    _ => fail("expected InvalidInput")
  }
  try @sys.File::open("bad\u{0}path") catch {
    e => {
      inspect(e, content="file name contained an unexpected NUL byte")
      assert_eq(e.code(), -1)
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "error display" {
  inspect(
    @sys.IOError::from_errno(2),
    content="No such file or directory (os error 2)",
  )
  inspect(
    @sys.IOError::from_errno(13),
    content="Permission denied (os error 13)",
  )
  inspect(@sys.IOError::from_errno(21), content="Is a directory (os error 21)")
  inspect(@sys.IOError::from_errno(20), content="Not a directory (os error 20)")
  // The message comes from the host's libc ("Unknown error 9999" with glibc,
  // "Unknown error: 9999" on macOS).
  let unknown = @sys.IOError::from_errno(9999).to_string()
  assert_true(unknown.has_prefix("Unknown error"))
  assert_true(unknown.has_suffix("9999 (os error 9999)"))
  debug_inspect(@sys.IOError::from_errno(13).kind(), content="PermissionDenied")
  debug_inspect(@sys.IOError::from_errno(32).kind(), content="BrokenPipe")
  inspect(
    @sys.IOError::other(Other, "custom message"),
    content="custom message",
  )
}

///|
test "process environment" {
  let args = @sys.args()
  assert_true(args.length() >= 1)
  assert_false(@sys.is_windows())
  assert_true(@sys.current_dir() is Some(_))
  assert_true(@sys.env_var("RGSYS_SURELY_NOT_SET_4242") is None)
  match @sys.env_var("PATH") {
    Some(path) =>
      assert_true(
        @sys.env_vars().iter().any(kv => kv.0 == "PATH" && kv.1 == path),
      )
    None => ()
  }
}

///|
test "stdio" {
  let msg = @utf8.encode("")
  let buf : FixedArray[Byte] = FixedArray::make(msg.length(), 0)
  // A zero-length write succeeds.
  @sys.write_fd(1, buf, 0, 0)
  try @sys.write_fd(1, buf, 0, 1) catch {
    e => debug_inspect(e.kind(), content="InvalidInput")
  } noraise {
    _ => fail("expected out of bounds error")
  }
}
