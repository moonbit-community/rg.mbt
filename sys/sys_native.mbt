// Native backend: thin wrappers over the C stubs in `sys_native.c`.

///|
extern "C" fn c_last_err() -> Int32 = "moonbit_rgsys_last_err"

///|
extern "C" fn c_cli_args() -> FixedArray[Bytes] = "moonbit_rt_get_cli_args"

///|
extern "C" fn c_exit(code : Int32) = "moonbit_rgsys_exit"

///|
#borrow(name)
extern "C" fn c_getenv(name : Bytes) -> Bytes = "moonbit_rgsys_getenv"

///|
extern "C" fn c_environ() -> Bytes = "moonbit_rgsys_environ"

///|
extern "C" fn c_getcwd() -> Bytes = "moonbit_rgsys_getcwd"

///|
extern "C" fn c_gethostname() -> Bytes = "moonbit_rgsys_gethostname"

///|
extern "C" fn c_now_nanos() -> Int64 = "moonbit_rgsys_now_nanos"

///|
#borrow(buf)
extern "C" fn c_write_all(
  fd : Int32,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Int32 = "moonbit_rgsys_write_all"

///|
#borrow(buf)
extern "C" fn c_read(
  fd : Int32,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Int32 = "moonbit_rgsys_read"

///|
extern "C" fn c_isatty(fd : Int32) -> Int32 = "moonbit_rgsys_isatty"

///|
extern "C" fn c_stdin_readable() -> Int32 = "moonbit_rgsys_stdin_readable"

///|
#borrow(path)
extern "C" fn c_open_read(path : Bytes) -> Int32 = "moonbit_rgsys_open_read"

///|
extern "C" fn c_close(fd : Int32) = "moonbit_rgsys_close"

///|
#borrow(path, data)
extern "C" fn c_write_file(path : Bytes, data : Bytes, len : Int32) -> Int32 = "moonbit_rgsys_write_file"

///|
#borrow(path)
extern "C" fn c_mkdir(path : Bytes) -> Int32 = "moonbit_rgsys_mkdir"

///|
#borrow(path)
extern "C" fn c_rmdir(path : Bytes) -> Int32 = "moonbit_rgsys_rmdir"

///|
#borrow(path)
extern "C" fn c_unlink(path : Bytes) -> Int32 = "moonbit_rgsys_unlink"

///|
#borrow(target, link)
extern "C" fn c_symlink(target : Bytes, link : Bytes) -> Int32 = "moonbit_rgsys_symlink"

///|
#borrow(path, out)
extern "C" fn c_stat(
  path : Bytes,
  follow : Int32,
  out : FixedArray[Int64],
) -> Int32 = "moonbit_rgsys_stat"

///|
#borrow(path)
extern "C" fn c_readdir(path : Bytes) -> Bytes = "moonbit_rgsys_readdir"

///|
#borrow(path)
extern "C" fn c_readlink(path : Bytes) -> Bytes = "moonbit_rgsys_readlink"

///|
#borrow(prog, argblob, stdin_path)
extern "C" fn c_run(
  prog : Bytes,
  argblob : Bytes,
  nargs : Int32,
  stdin_path : Bytes,
) -> Bytes = "moonbit_rgsys_run"

///|
fn last_error() -> IOError {
  IOError::from_errno(c_last_err())
}

///|
/// NUL-terminated UTF-8 encoding of `s` for passing to C.
fn cstr(s : String) -> Bytes raise IOError {
  let b = path_bytes(s)
  let out = FixedArray::make(b.length() + 1, b'\x00')
  out.blit_from_bytes(0, b, 0, b.length())
  out.unsafe_reinterpret_as_bytes()
}

///|
fn decode(b : BytesView) -> String {
  @utf8.decode_lossy(b)
}

///|
/// Splits a blob of NUL-terminated strings.
fn split_nul(b : Bytes) -> Array[BytesView] {
  let out = []
  let mut start = 0
  for i in 0..<b.length() {
    if b[i] == 0 {
      out.push(b[start:i])
      start = i + 1
    }
  }
  out
}

///|
/// The command line arguments, including the program name.
pub fn args() -> Array[String] {
  [
    for a in c_cli_args() => decode(a)
  ]
}

///|
/// The value of the environment variable `name`, if set.
pub fn env_var(name : String) -> String? {
  let n = cstr(name) catch { _ => return None }
  let b = c_getenv(n)
  if b.length() == 0 {
    None
  } else {
    Some(decode(b[1:]))
  }
}

///|
/// All environment variables.
pub fn env_vars() -> Array[(String, String)] {
  let out = []
  for entry in split_nul(c_environ()) {
    let s = decode(entry)
    match s.find("=") {
      Some(i) =>
        out.push(
          (
            s.unsafe_substring(start=0, end=i),
            s.unsafe_substring(start=i + 1, end=s.length()),
          ),
        )
      None => out.push((s, ""))
    }
  }
  out
}

///|
/// Terminates the process with the given exit code.
pub fn exit(code : Int32) -> Unit {
  c_exit(code)
}

///|
/// The current working directory.
pub fn current_dir() -> String? {
  let b = c_getcwd()
  if c_last_err() != 0 {
    None
  } else {
    Some(decode(b))
  }
}

///|
/// The host name of the machine.
pub fn hostname() -> String? {
  let b = c_gethostname()
  if c_last_err() != 0 {
    None
  } else {
    Some(decode(b))
  }
}

///|
pub fn is_windows() -> Bool {
  false
}

///|
/// A monotonic clock reading in nanoseconds.
pub fn now_nanos() -> Int64 {
  c_now_nanos()
}

///|
/// Writes all of `buf[start:start + len]` to `fd`.
pub fn write_fd(
  fd : Int32,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Unit raise IOError {
  check_range(buf.length(), start, len)
  if c_write_all(fd, buf, start, len) < 0 {
    raise last_error()
  }
}

///|
/// Reads up to `len` bytes from `fd` into `buf[start:start + len]`. Returns
/// `0` at end of file.
pub fn read_fd(
  fd : Int32,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Int32 raise IOError {
  check_range(buf.length(), start, len)
  let n = c_read(fd, buf, start, len)
  if n < 0 {
    raise last_error()
  }
  n
}

///|
/// Whether `fd` refers to a terminal.
pub fn is_tty(fd : Int32) -> Bool {
  c_isatty(fd) != 0
}

///|
/// Whether stdin is a file, a pipe/FIFO or a socket (and not a terminal).
pub fn stdin_is_readable() -> Bool {
  c_stdin_readable() != 0
}

///|
fn sys_open_read(path : String) -> Int32 raise IOError {
  let fd = c_open_read(cstr(path))
  if fd < 0 {
    raise last_error()
  }
  fd
}

///|
fn sys_close(fd : Int32) -> Unit {
  c_close(fd)
}

///|
fn sys_mkdir(path : String) -> Unit raise IOError {
  if c_mkdir(cstr(path)) < 0 {
    raise last_error()
  }
}

///|
fn sys_rmdir(path : String) -> Unit raise IOError {
  if c_rmdir(cstr(path)) < 0 {
    raise last_error()
  }
}

///|
/// Writes `data` to the file at `path`, creating or truncating it.
pub fn write_file(path : String, data : Bytes) -> Unit raise IOError {
  if c_write_file(cstr(path), data, data.length()) < 0 {
    raise last_error()
  }
}

///|
/// Removes a file (or symlink).
pub fn remove_file(path : String) -> Unit raise IOError {
  if c_unlink(cstr(path)) < 0 {
    raise last_error()
  }
}

///|
/// Creates a symlink at `link` pointing to `target`.
pub fn symlink(target : String, link : String) -> Unit raise IOError {
  if c_symlink(cstr(target), cstr(link)) < 0 {
    raise last_error()
  }
}

///|
fn kind_to_file_type(kind : Int32) -> FileType? {
  match kind {
    0 => None
    1 => Some(File)
    2 => Some(Dir)
    3 => Some(Symlink)
    _ => Some(Other)
  }
}

///|
fn stat_impl(path : String, follow : Bool) -> Metadata raise IOError {
  let out : FixedArray[Int64] = FixedArray::make(4, 0)
  if c_stat(cstr(path), if follow { 1 } else { 0 }, out) < 0 {
    raise last_error()
  }
  {
    file_type: kind_to_file_type(out[0].to_int()).unwrap_or(Other),
    len: out[1],
    dev: out[2].reinterpret_as_uint64(),
    ino: out[3].reinterpret_as_uint64(),
  }
}

///|
/// The length of the file at `path` (following symlinks).
pub fn file_len(path : String) -> Int64 raise IOError {
  metadata(path).len
}

///|
/// Metadata for `path`, following symlinks.
pub fn metadata(path : String) -> Metadata raise IOError {
  stat_impl(path, true)
}

///|
/// Metadata for `path`, without following a final symlink.
pub fn symlink_metadata(path : String) -> Metadata raise IOError {
  stat_impl(path, false)
}

///|
/// Lists the entries of the directory at `path` (excluding `.` and `..`).
pub fn read_dir(path : String) -> Array[DirEntry] raise IOError {
  let blob = c_readdir(cstr(path))
  if c_last_err() != 0 {
    raise last_error()
  }
  [
    for e in split_nul(blob) => {
      { name: decode(e[1:]), file_type: kind_to_file_type(e[0].to_int()), }
    }
  ]
}

///|
/// The target of the symlink at `path`.
pub fn read_link(path : String) -> String raise IOError {
  let b = c_readlink(cstr(path))
  if c_last_err() != 0 {
    raise last_error()
  }
  decode(b)
}

///|
fn read_i32_le(b : Bytes, i : Int32) -> Int32 {
  b[i].to_int() |
  (b[i + 1].to_int() << 8) |
  (b[i + 2].to_int() << 16) |
  (b[i + 3].to_int() << 24)
}

///|
/// Runs `program` (looked up in `PATH`) with `args`, capturing its stdout
/// and stderr. The child's stdin is the file at `stdin_path`, or `/dev/null`.
pub fn run_command(
  program : String,
  args : Array[String],
  stdin_path? : String,
) -> ProcessOutput raise IOError {
  let parts = []
  for a in args {
    parts.push(cstr(a))
  }
  let total = parts.fold(init=0, (acc, p) => acc + p.length())
  let argblob = FixedArray::make(total + 1, b'\x00')
  let mut off = 0
  for p in parts {
    argblob.blit_from_bytes(off, p, 0, p.length())
    off += p.length()
  }
  let stdin = cstr(stdin_path.unwrap_or("/dev/null"))
  let r = c_run(
    cstr(program),
    argblob.unsafe_reinterpret_as_bytes(),
    args.length(),
    stdin,
  )
  if r.length() < 8 {
    raise last_error()
  }
  let status = read_i32_le(r, 0)
  let out_len = read_i32_le(r, 4)
  {
    status,
    stdout: r[8:8 + out_len].to_owned(),
    stderr: r[8 + out_len:].to_owned(),
  }
}

///|
#borrow(path, out)
extern "C" fn c_file_times(path : Bytes, out : FixedArray[Int64]) -> Int32 = "moonbit_rgsys_file_times"

///|
/// Returns the modification, access and creation times of `path`
/// (following symlinks).
pub fn file_times(path : String) -> FileTimes raise IOError {
  let out : FixedArray[Int64] = FixedArray::make(9, 0)
  if c_file_times(cstr(path), out) < 0 {
    raise last_error()
  }
  let get = (i : Int32) => {
    if out[i + 2] != 0L {
      Some(out[i] * 1000000000L + out[i + 1])
    } else {
      None
    }
  }
  { modified: get(0), accessed: get(3), created: get(6), }
}
