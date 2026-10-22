// File system helpers for the (native only) tests that need a scratch
// directory, mirroring the `TempDir` helper of the Rust test suite.

///|
/// A scratch directory under `<cwd>/_build/tmp-ignore-tests/<name>`.
priv struct TempDir(String)

///|
fn TempDir::new(name : String) -> TempDir {
  let cwd = @sys.current_dir().unwrap()
  let path = cwd + "/_build/tmp-ignore-tests/" + name
  let exists = try {
    @sys.symlink_metadata(path) |> ignore
    true
  } catch {
    _ => false
  }
  if exists {
    @sys.remove_dir_all(path) catch {
      e => abort("failed to remove \{path}: \{e}")
    }
  }
  @sys.create_dir_all(path) catch {
    e => abort("failed to create \{path}: \{e}")
  }
  TempDir(path)
}

///|
fn TempDir::path(self : TempDir) -> String {
  self.0
}

///|
fn TempDir::join(self : TempDir, p : String) -> String {
  path_join(self.0, p)
}

///|
fn TempDir::close(self : TempDir) -> Unit {
  @sys.remove_dir_all(self.0) catch {
    e => abort("failed to remove \{self.0}: \{e}")
  }
}

///|
fn wfile(path : String, contents : String) -> Unit {
  @sys.write_file(path, @utf8.encode(contents)) catch {
    e => abort("failed to write \{path}: \{e}")
  }
}

///|
fn wfile_size(path : String, size : Int32) -> Unit {
  @sys.write_file(path, Bytes::make(size, b'\x00')) catch {
    e => abort("failed to write \{path}: \{e}")
  }
}

///|
fn mkdirp(path : String) -> Unit {
  @sys.create_dir_all(path) catch {
    e => abort("failed to create \{path}: \{e}")
  }
}

///|
fn symlink(src : String, dst : String) -> Unit {
  @sys.symlink(src, dst) catch {
    e => abort("failed to symlink \{dst} -> \{src}: \{e}")
  }
}
