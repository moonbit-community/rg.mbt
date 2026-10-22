///|
/// The type of a file system entry.
pub(all) enum FileType {
  File
  Dir
  Symlink
  Other
} derive(Eq, Debug)

///|
/// Metadata about a file system entry.
///
/// `dev` and `ino` are `0` on wasm (WASI preview1 as implemented by all
/// supported runners does not expose them without `fd_filestat_get`).
pub(all) struct Metadata {
  file_type : FileType
  len : Int64
  dev : UInt64
  ino : UInt64
} derive(Eq, Debug)

///|
pub fn Metadata::is_file(self : Metadata) -> Bool {
  self.file_type is File
}

///|
pub fn Metadata::is_dir(self : Metadata) -> Bool {
  self.file_type is Dir
}

///|
pub fn Metadata::is_symlink(self : Metadata) -> Bool {
  self.file_type is Symlink
}

///|
/// An entry returned by `read_dir`.
///
/// `file_type` is the type reported by the directory listing itself
/// (`d_type` / WASI `dirent.d_type`), without following symlinks, or `None`
/// when the OS does not know it.
pub(all) struct DirEntry {
  name : String
  file_type : FileType?
} derive(Eq, Debug)

///|
/// The result of `run_command`.
pub(all) struct ProcessOutput {
  status : Int32
  stdout : Bytes
  stderr : Bytes
} derive(Eq, Debug)

///|
/// An open file (a thin wrapper around a file descriptor).
pub struct File {
  priv fd : Int32
  priv mut closed : Bool
}

///|
/// The underlying file descriptor.
pub fn File::fd(self : File) -> Int32 {
  self.fd
}

///|
/// File timestamps, as nanoseconds since the Unix epoch. A field is `None`
/// if the platform doesn't provide it.
pub(all) struct FileTimes {
  modified : Int64?
  accessed : Int64?
  created : Int64?
} derive(Eq, Debug)
