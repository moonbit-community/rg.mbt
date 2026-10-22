///|
/// Parses the contents of a ripgrep config file: one argument per line,
/// ignoring blank lines and lines starting with `#` (after trimming).
/// Returns the arguments and any per-line errors.
pub fn parse_config_bytes(data : Bytes) -> (Array[String], Array[String]) {
  let args = []
  let errs = []
  let mut line_number = 0
  let mut start = 0
  let n = data.length()
  while start < n {
    let mut end = start
    while end < n && data[end] != b'\n' {
      end += 1
    }
    line_number += 1
    // Trim ASCII/Unicode whitespace like bstr's `trim` on the line
    // (including its terminator).
    let line = data[start:end]
    let mut s = 0
    let mut e = line.length()
    while s < e && is_ascii_ws(line[s]) {
      s += 1
    }
    while e > s && is_ascii_ws(line[e - 1]) {
      e -= 1
    }
    let trimmed = line[s:e]
    start = end + 1
    if trimmed.length() == 0 || trimmed[0] == b'#' {
      continue
    }
    // On Unix, ripgrep accepts arbitrary bytes here (OS strings). Since
    // arguments are strings in this port, invalid UTF-8 is decoded lossily.
    ignore(line_number)
    args.push(@utf8.decode_lossy(trimmed))
  }
  (args, errs)
}

///|
fn is_ascii_ws(b : Byte) -> Bool {
  b == b' ' ||
  b == b'\t' ||
  b == b'\n' ||
  b == b'\r' ||
  b == b'\x0B' ||
  b == b'\x0C'
}

///|
/// Reads extra arguments from the file in `RIPGREP_CONFIG_PATH`, if set.
pub fn config_args() -> Array[String] {
  let config_path = match @sys.env_var("RIPGREP_CONFIG_PATH") {
    None => {
      log_debug(
        "rg::flags::config", "RIPGREP_CONFIG_PATH environment variable is not set, therefore not reading any config file",
      )
      return []
    }
    Some(p) => {
      if p.is_empty() {
        return []
      }
      p
    }
  }
  let data = @sys.read_file(config_path) catch {
    e => {
      message(
        "failed to read the file specified in RIPGREP_CONFIG_PATH: \{config_path}: \{e}",
      )
      return []
    }
  }
  let (args, errs) = parse_config_bytes(data)
  for err in errs {
    message("\{config_path}:\{err}")
  }
  log_debug(
    "rg::flags::config",
    "\{config_path}: arguments loaded from config file: \{Repr(args)}",
  )
  args
}
