// Wasm (linear memory) backend on top of WASI preview1.
//
// Only the WASI functions implemented by BOTH wasmtime and moonrun (the
// runner used by `moon run --target wasm` / `moon test --target wasm`) are
// imported: importing anything else (e.g. `fd_filestat_get`) makes the module
// fail to instantiate under moonrun. File types are therefore derived from
// `fd_readdir` dirents, `path_readlink` and `path_open` with `O_DIRECTORY`.

// ---------------------------------------------------------------------------
// WASI imports.

///|
fn wasi_args_sizes_get(argc : Int32, size : Int32) -> Int32 = "wasi_snapshot_preview1" "args_sizes_get"

///|
fn wasi_args_get(argv : Int32, buf : Int32) -> Int32 = "wasi_snapshot_preview1" "args_get"

///|
fn wasi_environ_sizes_get(count : Int32, size : Int32) -> Int32 = "wasi_snapshot_preview1" "environ_sizes_get"

///|
fn wasi_environ_get(environ : Int32, buf : Int32) -> Int32 = "wasi_snapshot_preview1" "environ_get"

///|
fn wasi_fd_write(
  fd : Int32,
  iovs : Int32,
  iovs_len : Int32,
  nwritten : Int32,
) -> Int32 = "wasi_snapshot_preview1" "fd_write"

///|
fn wasi_fd_read(
  fd : Int32,
  iovs : Int32,
  iovs_len : Int32,
  nread : Int32,
) -> Int32 = "wasi_snapshot_preview1" "fd_read"

///|
fn wasi_fd_close(fd : Int32) -> Int32 = "wasi_snapshot_preview1" "fd_close"

///|
fn wasi_fd_prestat_get(fd : Int32, buf : Int32) -> Int32 = "wasi_snapshot_preview1" "fd_prestat_get"

///|
fn wasi_fd_prestat_dir_name(fd : Int32, path : Int32, len : Int32) -> Int32 = "wasi_snapshot_preview1" "fd_prestat_dir_name"

///|
fn wasi_fd_readdir(
  fd : Int32,
  buf : Int32,
  buf_len : Int32,
  cookie : Int64,
  buf_used : Int32,
) -> Int32 = "wasi_snapshot_preview1" "fd_readdir"

///|
fn wasi_path_open(
  dirfd : Int32,
  dirflags : Int32,
  path : Int32,
  path_len : Int32,
  oflags : Int32,
  rights_base : Int64,
  rights_inheriting : Int64,
  fdflags : Int32,
  fd_out : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_open"

///|
fn wasi_path_readlink(
  dirfd : Int32,
  path : Int32,
  path_len : Int32,
  buf : Int32,
  buf_len : Int32,
  buf_used : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_readlink"

///|
fn wasi_path_create_directory(
  dirfd : Int32,
  path : Int32,
  path_len : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_create_directory"

///|
fn wasi_path_remove_directory(
  dirfd : Int32,
  path : Int32,
  path_len : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_remove_directory"

///|
fn wasi_proc_exit(code : Int32) = "wasi_snapshot_preview1" "proc_exit"

// ---------------------------------------------------------------------------
// Memory helpers. The `*_ptr` functions take ownership of one reference to
// the array so that it stays alive while WASI uses the raw pointer; release
// it with `release` once the call is done.

///|
#owned(b)
extern "wasm" fn bytes_ptr(b : FixedArray[Byte]) -> Int32 =
  #|(func (param i32) (result i32) local.get 0)

///|
#owned(b)
extern "wasm" fn ints_ptr(b : FixedArray[Int32]) -> Int32 =
  #|(func (param i32) (result i32) local.get 0)

///|
extern "wasm" fn release(p : Int32) =
  #|(func (param i32) local.get 0 call $moonbit.decref)

// ---------------------------------------------------------------------------
// WASI constants.

///|
const ERRNO_BADF : Int32 = 8

///|
const ERRNO_INVAL : Int32 = 28

///|
const ERRNO_NOTDIR : Int32 = 54

///|
const ERRNO_NOTCAPABLE : Int32 = 76

///|
const LOOKUP_SYMLINK_FOLLOW : Int32 = 1

///|
const OFLAGS_CREAT : Int32 = 1

///|
const OFLAGS_DIRECTORY : Int32 = 2

///|
const OFLAGS_TRUNC : Int32 = 8

///|
const RIGHT_FD_READ : Int64 = 0x2

///|
const RIGHT_FD_SEEK : Int64 = 0x4

///|
const RIGHT_FD_TELL : Int64 = 0x20

///|
const RIGHT_FD_WRITE : Int64 = 0x40

///|
const RIGHT_FD_READDIR : Int64 = 0x4000

///|
const RIGHT_FD_FILESTAT_GET : Int64 = 0x200000

///|
/// Rights for reading a regular file (no write-ish rights, so that runners
/// open the file read-only).
let rights_read : Int64 = RIGHT_FD_READ |
  RIGHT_FD_SEEK |
  RIGHT_FD_TELL |
  RIGHT_FD_FILESTAT_GET

///|
let rights_write : Int64 = RIGHT_FD_WRITE |
  RIGHT_FD_SEEK |
  RIGHT_FD_TELL |
  RIGHT_FD_FILESTAT_GET

///|
let rights_dir : Int64 = RIGHT_FD_READDIR | RIGHT_FD_FILESTAT_GET | 0x71FBE00 // path_* rights

///|
let rights_all : Int64 = 0x1FFFFFFF

///|
fn wasi_error(errno : Int32) -> IOError {
  last_wasi_errno.val = errno
  IOError::from_errno(wasi_errno_to_linux(errno))
}

///|
/// The raw WASI errno of the last error built by `wasi_error`.
let last_wasi_errno : Ref[Int32] = { val: 0, }

///|
fn unsupported() -> IOError {
  IOError::other(Unsupported, "operation not supported on this platform")
}

///|
fn decode(b : BytesView) -> String {
  // Lossless: invalid UTF-8 (e.g. in file names) is escaped (see `osstr`).
  @osstr.decode(b)
}

// ---------------------------------------------------------------------------
// Process / environment.

///|
/// Reads a NUL-separated string table (args or environ).
fn read_string_table(
  sizes_get : (Int32, Int32) -> Int32,
  get : (Int32, Int32) -> Int32,
) -> Array[String] {
  let sizes : FixedArray[Int32] = FixedArray::make(2, 0)
  let sp = ints_ptr(sizes)
  let rc = sizes_get(sp, sp + 4)
  release(sp)
  if rc != 0 {
    return []
  }
  let count = sizes[0]
  let size = sizes[1]
  if count == 0 {
    return []
  }
  let ptrs : FixedArray[Int32] = FixedArray::make(count, 0)
  let buf : FixedArray[Byte] = FixedArray::make(size, 0)
  let pp = ints_ptr(ptrs)
  let bp = bytes_ptr(buf)
  let rc = get(pp, bp)
  release(pp)
  release(bp)
  if rc != 0 {
    return []
  }
  let bytes = buf.unsafe_reinterpret_as_bytes()
  let out = []
  let mut start = 0
  for i in 0..<size {
    if buf[i] == 0 {
      out.push(decode(bytes[start:i]))
      start = i + 1
    }
  }
  out
}

///|
/// The command line arguments, including the program name.
pub fn args() -> Array[String] {
  read_string_table(wasi_args_sizes_get, wasi_args_get)
}

///|
/// All environment variables.
pub fn env_vars() -> Array[(String, String)] {
  environ().copy()
}

///|
/// WASI has no way to modify the environment, so it is read once.
let environ_cache : Ref[Array[(String, String)]?] = { val: None, }

///|
fn environ() -> Array[(String, String)] {
  if environ_cache.val is Some(env) {
    return env
  }
  let out = []
  for s in read_string_table(wasi_environ_sizes_get, wasi_environ_get) {
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
  environ_cache.val = Some(out)
  out
}

///|
/// The value of the environment variable `name`, if set.
pub fn env_var(name : String) -> String? {
  for kv in environ() {
    if kv.0 == name {
      return Some(kv.1)
    }
  }
  None
}

///|
/// Terminates the process with the given exit code.
pub fn exit(code : Int32) -> Unit {
  wasi_proc_exit(code)
}

///|
/// The current working directory: `$PWD` if set, otherwise `"."`.
pub fn current_dir() -> String? {
  match env_var("PWD") {
    Some(pwd) if pwd != "" => Some(pwd)
    _ => Some(".")
  }
}

///|
/// Always `None` on wasm.
pub fn hostname() -> String? {
  None
}

///|
/// A no-op on wasm (there are no signals).
pub fn ignore_sigpipe() -> Unit {
  ()
}

///|
pub fn is_windows() -> Bool {
  false
}

///|
/// Whether ripgrep would search files through memory maps on this platform.
/// Always `false` on wasm (WASI has no memory maps).
pub fn mmap_supported() -> Bool {
  false
}

///|
/// Always `0` on wasm (`clock_time_get` is not available under moonrun).
pub fn now_nanos() -> Int64 {
  0
}

// ---------------------------------------------------------------------------
// File descriptors.

///|
/// Writes all of `buf[start:start + len]` to `fd`.
pub fn write_fd(
  fd : Int32,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Unit raise IOError {
  check_range(buf.length(), start, len)
  let scratch : FixedArray[Int32] = FixedArray::make(3, 0)
  let sp = ints_ptr(scratch)
  let bp = bytes_ptr(buf)
  defer {
    release(sp)
    release(bp)
  }
  let mut off = start
  let mut remaining = len
  while remaining > 0 {
    scratch[0] = bp + off
    scratch[1] = remaining
    let rc = wasi_fd_write(fd, sp, 1, sp + 8)
    if rc != 0 {
      raise wasi_error(rc)
    }
    let n = scratch[2]
    if n <= 0 {
      raise IOError::other(Other, "failed to write whole buffer")
    }
    off += n
    remaining -= n
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
  let scratch : FixedArray[Int32] = FixedArray::make(3, 0)
  let sp = ints_ptr(scratch)
  let bp = bytes_ptr(buf)
  defer {
    release(sp)
    release(bp)
  }
  scratch[0] = bp + start
  scratch[1] = len
  let rc = wasi_fd_read(fd, sp, 1, sp + 8)
  if rc != 0 {
    raise wasi_error(rc)
  }
  scratch[2]
}

///|
/// Always `false` on wasm (`fd_fdstat_get` is not available under moonrun).
pub fn is_tty(fd : Int32) -> Bool {
  ignore(fd)
  false
}

///|
/// Always `false` on wasm: whether stdin is a pipe or a file cannot be
/// determined without `fd_fdstat_get`. Callers should read stdin when asked
/// to explicitly (e.g. a `-` path).
pub fn stdin_is_readable() -> Bool {
  false
}

///|
fn sys_close(fd : Int32) -> Unit {
  ignore(wasi_fd_close(fd))
}

// ---------------------------------------------------------------------------
// Preopened directories and path resolution.

///|
priv struct Preopen {
  fd : Int32
  name : String
}

///|
let preopen_cache : Ref[Array[Preopen]?] = { val: None, }

///|
fn strip_dot_slash(s : String) -> String {
  let mut p = s
  while p.has_prefix("./") {
    let mut i = 2
    while i < p.length() && p[i] == '/' {
      i += 1
    }
    p = p.unsafe_substring(start=i, end=p.length())
  }
  p
}

///|
fn normalize_preopen_name(s : String) -> String {
  let mut p = strip_dot_slash(s)
  while p.length() > 1 && p.has_suffix("/") {
    p = p.unsafe_substring(start=0, end=p.length() - 1)
  }
  if p == "" {
    "."
  } else {
    p
  }
}

///|
fn preopens() -> Array[Preopen] {
  if preopen_cache.val is Some(p) {
    return p
  }
  let out = []
  let st : FixedArray[Int32] = FixedArray::make(2, 0)
  for fd = 3; ; fd = fd + 1 {
    let sp = ints_ptr(st)
    let rc = wasi_fd_prestat_get(fd, sp)
    release(sp)
    if rc == ERRNO_BADF {
      break
    }
    if rc != 0 || (st[0] & 0xff) != 0 {
      continue
    }
    let len = st[1]
    let name : FixedArray[Byte] = FixedArray::make(len, 0)
    let np = bytes_ptr(name)
    let rc = wasi_fd_prestat_dir_name(fd, np, len)
    release(np)
    if rc != 0 {
      continue
    }
    // Some runners include a trailing NUL in the name.
    let mut n = len
    while n > 0 && name[n - 1] == 0 {
      n -= 1
    }
    let s = decode(name.unsafe_reinterpret_as_bytes()[0:n])
    out.push({ fd, name: normalize_preopen_name(s), })
  }
  preopen_cache.val = Some(out)
  out
}

///|
/// If `path` is `name` or lies below it, the remainder relative to `name`.
fn match_prefix(path : String, name : String) -> String? {
  let rest = if name == "/" {
    if !path.has_prefix("/") {
      return None
    }
    path
  } else if path == name {
    ""
  } else if path.has_prefix(name) && path[name.length()] == '/' {
    path.unsafe_substring(start=name.length(), end=path.length())
  } else {
    return None
  }
  let mut i = 0
  while i < rest.length() && rest[i] == '/' {
    i += 1
  }
  let rel = rest.unsafe_substring(start=i, end=rest.length())
  Some(if rel == "" { "." } else { rel })
}

///|
/// Finds the preopen with the longest name matching `path`, considering only
/// absolute or only relative preopen names. `"."` is never matched here.
fn best_preopen(path : String, absolute : Bool) -> (Int32, String)? {
  let mut best : (Int32, String)? = None
  let mut best_len = -1
  for p in preopens() {
    if p.name == "." || p.name.has_prefix("/") != absolute {
      continue
    }
    if match_prefix(path, p.name) is Some(rel) && p.name.length() > best_len {
      best = Some((p.fd, rel))
      best_len = p.name.length()
    }
  }
  best
}

///|
fn dot_preopen() -> Int32? {
  for p in preopens() {
    if p.name == "." {
      return Some(p.fd)
    }
  }
  None
}

///|
/// Lexically normalizes an absolute path: removes empty and `.` components
/// and resolves `..` against the preceding component.
fn normalize_abs(path : String) -> String {
  let parts : Array[String] = []
  for c in path.split("/") {
    let c = c.to_owned()
    if c == "" || c == "." {
      continue
    } else if c == ".." {
      ignore(parts.pop())
    } else {
      parts.push(c)
    }
  }
  "/" + parts.join("/")
}

///|
/// Maps `path` to a preopened directory fd and a path relative to it.
fn resolve(path : String) -> (Int32, String) raise IOError {
  if path == "" {
    raise IOError::from_errno(2)
  }
  let p = strip_dot_slash(path)
  let p = if p == "" { "." } else { p }
  if p.has_prefix("/") {
    if best_preopen(p, true) is Some(r) {
      return r
    }
    match (env_var("PWD"), dot_preopen()) {
      (Some(pwd), Some(dot)) if pwd.has_prefix("/") =>
        if match_prefix(p, normalize_preopen_name(pwd)) is Some(rel) {
          return (dot, rel)
        }
      _ => ()
    }
    raise no_preopen(path)
  }
  if best_preopen(p, false) is Some(r) {
    return r
  }
  // A path escaping the current directory (e.g. `../x`) can't be opened
  // through the `.` preopen, so go through an absolute preopen instead.
  if p.split("/").any(c => c == "..") {
    match env_var("PWD") {
      Some(pwd) if pwd.has_prefix("/") =>
        if best_preopen(normalize_abs(pwd + "/" + p), true) is Some(r) {
          return r
        }
      _ => ()
    }
  }
  if dot_preopen() is Some(dot) {
    return (dot, p)
  }
  match env_var("PWD") {
    Some(pwd) if pwd.has_prefix("/") => {
      let abs = if pwd.has_suffix("/") { pwd + p } else { pwd + "/" + p }
      if best_preopen(abs, true) is Some(r) {
        return r
      }
    }
    _ => ()
  }
  raise no_preopen(path)
}

///|
/// The error for a path not below any preopened directory (same message as
/// Rust's standard library on WASI).
fn no_preopen(path : String) -> IOError {
  IOError::other(
    Other,
    "failed to find a pre-opened file descriptor through which \{Repr(path)} could be opened",
  )
}

///|
/// Opens `rel` relative to `dirfd`. Returns the fd or a WASI errno (as a
/// negative number).
fn open_at(
  dirfd : Int32,
  rel : String,
  follow~ : Bool,
  oflags~ : Int32,
  rights~ : Int64,
) -> Int32 raise IOError {
  let pb = path_bytes(rel)
  let path : FixedArray[Byte] = FixedArray::make(pb.length(), 0)
  path.blit_from_bytes(0, pb, 0, pb.length())
  let out : FixedArray[Int32] = FixedArray::make(1, -1)
  let pp = bytes_ptr(path)
  let op = ints_ptr(out)
  let rc = wasi_path_open(
    dirfd,
    if follow {
      LOOKUP_SYMLINK_FOLLOW
    } else {
      0
    },
    pp,
    pb.length(),
    oflags,
    rights,
    rights_all,
    0,
    op,
  )
  release(pp)
  release(op)
  if rc != 0 {
    -rc
  } else {
    out[0]
  }
}

///|
fn open_path(
  path : String,
  oflags~ : Int32,
  rights~ : Int64,
  follow~ : Bool = true,
) -> Int32 raise IOError {
  let (dirfd, rel) = resolve(path)
  let fd = open_at(dirfd, rel, follow~, oflags~, rights~)
  if fd < 0 {
    raise wasi_error(-fd)
  }
  fd
}

///|
/// Calls a WASI `path_*` function taking `(dirfd, path_ptr, path_len)`.
fn path_call(
  path : String,
  f : (Int32, Int32, Int32) -> Int32,
) -> Unit raise IOError {
  let (dirfd, rel) = resolve(path)
  let pb = path_bytes(rel)
  let buf : FixedArray[Byte] = FixedArray::make(pb.length(), 0)
  buf.blit_from_bytes(0, pb, 0, pb.length())
  let bp = bytes_ptr(buf)
  let rc = f(dirfd, bp, pb.length())
  release(bp)
  if rc != 0 {
    raise wasi_error(rc)
  }
}

// ---------------------------------------------------------------------------
// Files and directories.

///|
fn sys_open_read(path : String) -> Int32 raise IOError {
  open_path(path, oflags=0, rights=rights_read)
}

///|
fn sys_mkdir(path : String) -> Unit raise IOError {
  path_call(path, wasi_path_create_directory)
}

///|
fn sys_rmdir(path : String) -> Unit raise IOError {
  path_call(path, wasi_path_remove_directory)
}

///|
/// Writes `data` to the file at `path`, creating or truncating it.
pub fn write_file(path : String, data : Bytes) -> Unit raise IOError {
  let fd = open_path(
    path,
    oflags=OFLAGS_CREAT | OFLAGS_TRUNC,
    rights=rights_write,
  )
  defer sys_close(fd)
  let buf : FixedArray[Byte] = FixedArray::make(data.length(), 0)
  buf.blit_from_bytes(0, data, 0, data.length())
  write_fd(fd, buf, 0, buf.length())
}

///|
/// Unsupported on wasm (`path_unlink_file` is not available under moonrun).
pub fn remove_file(path : String) -> Unit raise IOError {
  ignore(path)
  raise unsupported()
}

///|
/// Unsupported on wasm (`path_symlink` is not available under moonrun).
pub fn symlink(target : String, link : String) -> Unit raise IOError {
  ignore(target)
  ignore(link)
  raise unsupported()
}

///|
/// Reads the symlink `rel` relative to `dirfd`. Returns `Err(errno)` on
/// failure.
fn readlink_at(
  dirfd : Int32,
  rel : String,
) -> Result[String, Int32] raise IOError {
  let pb = path_bytes(rel)
  let path : FixedArray[Byte] = FixedArray::make(pb.length(), 0)
  path.blit_from_bytes(0, pb, 0, pb.length())
  for cap = 256; ; cap = cap * 2 {
    let buf : FixedArray[Byte] = FixedArray::make(cap, 0)
    let used : FixedArray[Int32] = FixedArray::make(1, 0)
    let pp = bytes_ptr(path)
    let bp = bytes_ptr(buf)
    let up = ints_ptr(used)
    let rc = wasi_path_readlink(dirfd, pp, pb.length(), bp, cap, up)
    release(pp)
    release(bp)
    release(up)
    if rc != 0 {
      return Err(rc)
    }
    if used[0] < cap {
      return Ok(decode(buf.unsafe_reinterpret_as_bytes()[0:used[0]]))
    }
  }
}

///|
/// Unsupported on wasm (like Rust's `std::fs::canonicalize` on WASI).
pub fn canonicalize(path : String) -> String raise IOError {
  ignore(path)
  raise unsupported()
}

///|
/// The target of the symlink at `path`.
pub fn read_link(path : String) -> String raise IOError {
  let (dirfd, rel) = resolve(path)
  match readlink_at(dirfd, rel) {
    Ok(s) => s
    Err(e) => raise wasi_error(e)
  }
}

///|
/// Counts the bytes readable from `fd`.
fn count_bytes(fd : Int32) -> Int64 raise IOError {
  let chunk : FixedArray[Byte] = FixedArray::make(65536, 0)
  let mut total = 0L
  for ;; {
    let n = read_fd(fd, chunk, 0, chunk.length())
    if n == 0 {
      break
    }
    total += n.to_int64()
  }
  total
}

///|
/// Determines the type of `rel` (relative to `dirfd`) by opening it.
fn probe_type(
  dirfd : Int32,
  rel : String,
  follow : Bool,
) -> Metadata raise IOError {
  let fd = open_at(
    dirfd,
    rel,
    follow~,
    oflags=OFLAGS_DIRECTORY,
    rights=rights_dir,
  )
  if fd >= 0 {
    sys_close(fd)
    return { file_type: Dir, len: 0, dev: 0, ino: 0, }
  }
  if -fd != ERRNO_NOTDIR {
    raise wasi_error(-fd)
  }
  let fd = open_at(dirfd, rel, follow~, oflags=0, rights=rights_read)
  if fd < 0 {
    raise wasi_error(-fd)
  }
  sys_close(fd)
  // There is no fstat, and computing the length means reading the whole
  // file, so it is left unknown (see `file_len`).
  { file_type: File, len: -1, dev: 0, ino: 0, }
}

///|
/// The length of the file at `path` (following symlinks).
///
/// On wasm there is no `fstat`, so the file is read to count its bytes.
pub fn file_len(path : String) -> Int64 raise IOError {
  let fd = sys_open_read(path)
  defer sys_close(fd)
  count_bytes(fd)
}

///|
/// Metadata for `path`, following symlinks.
///
/// On wasm, `dev`/`ino` are `0`, every non-directory is reported as `File`,
/// and `len` is computed by reading the file.
pub fn metadata(path : String) -> Metadata raise IOError {
  let (dirfd, rel) = resolve(path)
  probe_type(dirfd, rel, true) catch {
    // moonrun reports a dangling symlink as `notcapable` (it cannot resolve
    // the target inside the sandbox); report it like the OS would.
    e if last_wasi_errno.val == ERRNO_NOTCAPABLE &&
      readlink_at(dirfd, rel) is Ok(_) => {
      ignore(e)
      raise IOError::from_errno(2)
    }
    e => raise e
  }
}

///|
/// Metadata for `path`, without following a final symlink.
pub fn symlink_metadata(path : String) -> Metadata raise IOError {
  let (dirfd, rel) = resolve(path)
  // moonrun refuses to readlink a preopened directory itself (`notcapable`),
  // which is never a symlink anyway.
  if rel == "." {
    return probe_type(dirfd, rel, false)
  }
  match readlink_at(dirfd, rel) {
    Ok(target) =>
      {
        file_type: Symlink,
        len: @osstr.encode(target).length().to_int64(),
        dev: 0,
        ino: 0,
      }
    Err(e) if e == ERRNO_INVAL => probe_type(dirfd, rel, false)
    Err(e) => raise wasi_error(e)
  }
}

///|
fn dirent_type(t : Int32) -> FileType? {
  match t {
    0 => None
    3 => Some(Dir)
    4 => Some(File)
    7 => Some(Symlink)
    _ => Some(Other)
  }
}

///|
fn le32(b : FixedArray[Byte], i : Int32) -> Int32 {
  b[i].to_int() |
  (b[i + 1].to_int() << 8) |
  (b[i + 2].to_int() << 16) |
  (b[i + 3].to_int() << 24)
}

///|
fn le64(b : FixedArray[Byte], i : Int32) -> Int64 {
  le32(b, i).reinterpret_as_uint().to_uint64().reinterpret_as_int64() |
  (le32(b, i + 4).to_int64() << 32)
}

///|
/// Lists the entries of the directory at `path` (excluding `.` and `..`).
pub fn read_dir(path : String) -> Array[DirEntry] raise IOError {
  let fd = open_path(path, oflags=OFLAGS_DIRECTORY, rights=rights_dir)
  defer sys_close(fd)
  let out = []
  let mut cookie = 0L
  let mut cap = 4096
  for ;; {
    let buf : FixedArray[Byte] = FixedArray::make(cap, 0)
    let used : FixedArray[Int32] = FixedArray::make(1, 0)
    let bp = bytes_ptr(buf)
    let up = ints_ptr(used)
    let rc = wasi_fd_readdir(fd, bp, cap, cookie, up)
    release(bp)
    release(up)
    if rc != 0 {
      raise wasi_error(rc)
    }
    let n = used[0]
    let bytes = buf.unsafe_reinterpret_as_bytes()
    let mut i = 0
    let mut parsed = 0
    while i + 24 <= n {
      let next = le64(buf, i)
      let namlen = le32(buf, i + 16)
      let typ = buf[i + 20].to_int()
      if i + 24 + namlen > n {
        break
      }
      let name = decode(bytes[i + 24:i + 24 + namlen])
      if name != "." && name != ".." {
        out.push({ name, file_type: dirent_type(typ), })
      }
      cookie = next
      parsed += 1
      i += 24 + namlen
    }
    if n < cap {
      // The buffer was not filled: end of directory.
      break
    }
    if parsed == 0 {
      // A single entry does not fit: grow the buffer.
      cap *= 2
    }
  }
  out
}

///|
/// Unsupported on wasm.
pub fn run_command(
  program : String,
  args : Array[String],
  stdin_path? : String,
) -> ProcessOutput raise IOError {
  ignore(program)
  ignore(args)
  ignore(stdin_path)
  raise unsupported()
}

///|
/// File timestamps are not available on wasm (no `fd_filestat_get` in the
/// supported WASI subset).
pub fn file_times(path : String) -> FileTimes raise IOError {
  ignore(path)
  raise IOError::other(Unsupported, "operation not supported on this platform")
}
