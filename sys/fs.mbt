///|
/// Opens a file for reading.
pub fn File::open(path : String) -> File raise IOError {
  { fd: sys_open_read(path), closed: false, }
}

///|
/// Reads up to `len` bytes into `buf[start:start + len]`. Returns the number
/// of bytes read, which is `0` at end of file.
pub fn File::read(
  self : File,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Int32 raise IOError {
  if self.closed {
    raise IOError::from_errno(9)
  }
  read_fd(self.fd, buf, start, len)
}

///|
/// Closes the file. Closing an already closed file does nothing.
pub fn File::close(self : File) -> Unit {
  if !self.closed {
    self.closed = true
    sys_close(self.fd)
  }
}

///|
/// Reads the whole file at `path`.
pub fn read_file(path : String) -> Bytes raise IOError {
  let file = File::open(path)
  defer file.close()
  read_to_end(file.fd)
}

///|
/// Reads everything from `fd` until end of file.
fn read_to_end(fd : Int32) -> Bytes raise IOError {
  let chunk : FixedArray[Byte] = FixedArray::make(65536, 0)
  let out = Buffer()
  for ;; {
    let n = read_fd(fd, chunk, 0, chunk.length())
    if n == 0 {
      break
    }
    out.write_bytesview(chunk.unsafe_reinterpret_as_bytes()[0:n])
  }
  out.to_bytes()
}

///|
/// Returns true if `path` exists (following symlinks).
pub fn path_exists(path : String) -> Bool {
  try metadata(path) catch {
    _ => return false
  } noraise {
    _ => true
  }
}

///|
fn is_dir_path(path : String) -> Bool {
  try metadata(path) catch {
    _ => return false
  } noraise {
    md => md.file_type is Dir
  }
}

///|
/// Returns the parent of `path` (lexically), or `None` if `path` has no
/// parent component (e.g. `"foo"` or `"/"`).
fn parent_path(path : String) -> String? {
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  for i = end - 1; i >= 0; i = i - 1 {
    if path[i] == '/' {
      let mut j = i
      while j > 0 && path[j - 1] == '/' {
        j -= 1
      }
      return Some(
        if j == 0 {
          "/"
        } else {
          path.unsafe_substring(start=0, end=j)
        },
      )
    }
  }
  None
}

///|
/// Recursively creates a directory and all of its missing parents.
pub fn create_dir_all(path : String) -> Unit raise IOError {
  if path == "" || is_dir_path(path) {
    return
  }
  try sys_mkdir(path) catch {
    e if e.kind() is NotFound => ()
    e => if is_dir_path(path) { return } else { raise e }
  } noraise {
    _ => return
  }
  match parent_path(path) {
    Some(parent) if parent != path => create_dir_all(parent)
    _ => raise IOError::other(Other, "failed to create whole tree")
  }
  sys_mkdir(path) catch {
    e => if !is_dir_path(path) { raise e }
  }
}

///|
/// Removes a directory after removing all of its contents. Symlinks are
/// removed, not followed.
pub fn remove_dir_all(path : String) -> Unit raise IOError {
  let md = symlink_metadata(path)
  if md.file_type is Dir {
    remove_dir_contents(path)
    sys_rmdir(path)
  } else {
    remove_file(path)
  }
}

///|
fn remove_dir_contents(path : String) -> Unit raise IOError {
  for entry in read_dir(path) {
    let child = join_path(path, entry.name)
    let ft = match entry.file_type {
      Some(ft) => ft
      None => symlink_metadata(child).file_type
    }
    if ft is Dir {
      remove_dir_contents(child)
      sys_rmdir(child)
    } else {
      remove_file(child)
    }
  }
}

///|
fn join_path(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn check_range(
  buf_len : Int32,
  start : Int32,
  len : Int32,
) -> Unit raise IOError {
  if start < 0 || len < 0 || start > buf_len - len {
    raise IOError::other(InvalidInput, "buffer range out of bounds")
  }
}

///|
/// Encodes `s` for the OS (as UTF-8, restoring bytes escaped by `osstr`),
/// rejecting interior NUL characters (like Rust does for paths passed to the
/// OS).
fn path_bytes(s : String) -> Bytes raise IOError {
  for c in s {
    if c == '\u{0}' {
      raise IOError::other(
        InvalidInput,
        "file name contained an unexpected NUL byte",
      )
    }
  }
  @osstr.encode(s)
}

///|
/// Runs `program` (looked up in `PATH`) with `args` to completion,
/// capturing its stdout and stderr. The child's stdin is the file at
/// `stdin_path`, or `/dev/null`.
pub fn run_command(
  program : String,
  args : Array[String],
  stdin_path? : String,
) -> ProcessOutput raise IOError {
  let child = Process::spawn(program, args, stdin_path?)
  let out = Buffer()
  let chunk = FixedArray::make(65536, b'\x00')
  for ;; {
    let n = child.read(chunk, 0, chunk.length())
    if n == 0 {
      break
    }
    out.write_bytes(chunk.unsafe_reinterpret_as_bytes()[0:n])
  }
  let (status, stderr) = child.finish()
  { status, stdout: out.to_bytes(), stderr, }
}
