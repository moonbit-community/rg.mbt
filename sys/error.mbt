///|
/// A coarse classification of I/O errors, modeled after Rust's
/// `std::io::ErrorKind`.
pub(all) enum IOErrorKind {
  NotFound
  PermissionDenied
  AlreadyExists
  InvalidInput
  Interrupted
  BrokenPipe
  IsADirectory
  NotADirectory
  Unsupported
  Other
} derive(Eq, Debug)

///|
/// An I/O error, modeled after Rust's `std::io::Error`.
///
/// `code` is a Linux-style errno number for OS errors (on every backend:
/// native errno values and WASI errno values are translated), or `-1` for
/// errors that do not originate from the operating system.
pub suberror IOError {
  IOError(kind~ : IOErrorKind, code~ : Int32, message~ : String)
} derive(Debug)

///|
/// Renders like Rust's `io::Error` `Display`:
/// `No such file or directory (os error 2)` for OS errors, or just the
/// message for other errors.
pub impl Show for IOError with fn output(self, logger) {
  let IOError(code~, message~, ..) = self
  logger.write_string(message)
  if code >= 0 {
    logger.write_string(" (os error ")
    logger.write_string(code.to_string())
    logger.write_string(")")
  }
}

///|
/// The kind of this error.
pub fn IOError::kind(self : IOError) -> IOErrorKind {
  let IOError(kind~, ..) = self
  kind
}

///|
/// The Linux-style errno of this error, or `-1` if it is not an OS error.
pub fn IOError::code(self : IOError) -> Int32 {
  let IOError(code~, ..) = self
  code
}

///|
/// The message of this error (without the ` (os error N)` suffix).
pub fn IOError::message(self : IOError) -> String {
  let IOError(message~, ..) = self
  message
}

///|
/// Builds an error from a Linux-style errno number.
pub fn IOError::from_errno(code : Int32) -> IOError {
  IOError(kind=errno_kind(code), code~, message=strerror(code))
}

///|
/// Builds an error that does not originate from the operating system.
pub fn IOError::other(kind : IOErrorKind, message : String) -> IOError {
  IOError(kind~, code=-1, message~)
}

///|
/// Maps a Linux errno to an error kind (mirrors Rust's `decode_error_kind`).
fn errno_kind(code : Int32) -> IOErrorKind {
  match code {
    1 | 13 => PermissionDenied
    2 => NotFound
    17 => AlreadyExists
    22 => InvalidInput
    4 => Interrupted
    32 => BrokenPipe
    21 => IsADirectory
    20 => NotADirectory
    38 | 95 => Unsupported
    _ => Other
  }
}

///|
/// Linux (glibc) `strerror` texts.
fn strerror(code : Int32) -> String {
  match code {
    1 => "Operation not permitted"
    2 => "No such file or directory"
    3 => "No such process"
    4 => "Interrupted system call"
    5 => "Input/output error"
    6 => "No such device or address"
    7 => "Argument list too long"
    8 => "Exec format error"
    9 => "Bad file descriptor"
    10 => "No child processes"
    11 => "Resource temporarily unavailable"
    12 => "Cannot allocate memory"
    13 => "Permission denied"
    14 => "Bad address"
    15 => "Block device required"
    16 => "Device or resource busy"
    17 => "File exists"
    18 => "Invalid cross-device link"
    19 => "No such device"
    20 => "Not a directory"
    21 => "Is a directory"
    22 => "Invalid argument"
    23 => "Too many open files in system"
    24 => "Too many open files"
    25 => "Inappropriate ioctl for device"
    26 => "Text file busy"
    27 => "File too large"
    28 => "No space left on device"
    29 => "Illegal seek"
    30 => "Read-only file system"
    31 => "Too many links"
    32 => "Broken pipe"
    33 => "Numerical argument out of domain"
    34 => "Numerical result out of range"
    35 => "Resource deadlock avoided"
    36 => "File name too long"
    37 => "No locks available"
    38 => "Function not implemented"
    39 => "Directory not empty"
    40 => "Too many levels of symbolic links"
    42 => "No message of desired type"
    43 => "Identifier removed"
    61 => "No data available"
    62 => "Timer expired"
    67 => "Link has been severed"
    71 => "Protocol error"
    72 => "Multihop attempted"
    74 => "Bad message"
    75 => "Value too large for defined data type"
    84 => "Invalid or incomplete multibyte or wide character"
    88 => "Socket operation on non-socket"
    89 => "Destination address required"
    90 => "Message too long"
    91 => "Protocol wrong type for socket"
    92 => "Protocol not available"
    93 => "Protocol not supported"
    95 => "Operation not supported"
    97 => "Address family not supported by protocol"
    98 => "Address already in use"
    99 => "Cannot assign requested address"
    100 => "Network is down"
    101 => "Network is unreachable"
    102 => "Network dropped connection on reset"
    103 => "Software caused connection abort"
    104 => "Connection reset by peer"
    105 => "No buffer space available"
    106 => "Transport endpoint is already connected"
    107 => "Transport endpoint is not connected"
    110 => "Connection timed out"
    111 => "Connection refused"
    113 => "No route to host"
    114 => "Operation already in progress"
    115 => "Operation now in progress"
    116 => "Stale file handle"
    122 => "Disk quota exceeded"
    125 => "Operation canceled"
    130 => "Owner died"
    131 => "State not recoverable"
    _ => "Unknown error \{code}"
  }
}
