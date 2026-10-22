///|
/// An error from running a command.
pub suberror CommandError {
  /// An I/O error (e.g. the command could not be spawned).
  CommandIo(@sys.IOError)
  /// The command failed; the payload is its stderr.
  CommandStderr(Bytes)
  /// Some other error message.
  CommandOther(String)
} derive(Debug)

///|
pub fn CommandError::to_string(self : CommandError) -> String {
  match self {
    CommandIo(e) => e.to_string()
    CommandOther(s) => s
    CommandStderr(bytes) => {
      let msg = @utf8.decode_lossy(bytes)
      if msg.trim().is_empty() {
        "<stderr is empty>"
      } else {
        let div = "-".repeat(79)
        "\n\{div}\n\{msg.trim()}\n\{div}"
      }
    }
  }
}

///|
pub impl Show for CommandError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Reads the stdout of a command. Since this platform layer can't stream
/// process output, the command is run to completion first.
pub struct CommandReader {
  priv output : @sys.ProcessOutput
  priv mut pos : Int32
  priv mut eof : Bool
  priv mut closed : Bool
}

///|
/// Runs `program` with `args`, optionally feeding `stdin_path` as stdin.
pub fn CommandReader::new(
  program : String,
  args : Array[String],
  stdin_path? : String,
) -> CommandReader raise CommandError {
  let output = @sys.run_command(program, args, stdin_path?) catch {
    e => raise CommandIo(e)
  }
  { output, pos: 0, eof: false, closed: false, }
}

///|
/// Reads into `buf[start:start+len]`. At the end of the output, raises an
/// error if the command exited unsuccessfully.
pub fn CommandReader::read(
  self : CommandReader,
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> Int32 raise CommandError {
  if self.closed {
    return 0
  }
  let out = self.output.stdout
  let avail = out.length() - self.pos
  if avail <= 0 {
    self.eof = true
    self.close()
    return 0
  }
  let n = if avail < len { avail } else { len }
  buf.blit_from_bytes(start, out, self.pos, n)
  self.pos += n
  n
}

///|
/// Closes the reader, raising an error if the command failed.
pub fn CommandReader::close(self : CommandReader) -> Unit raise CommandError {
  if self.closed {
    return
  }
  self.closed = true
  if self.output.status == 0 {
    return
  }
  if !self.eof && self.output.stderr.length() == 0 {
    return
  }
  raise CommandStderr(self.output.stderr)
}

///|
/// Returns all of the command's stdout, raising if it failed.
pub fn CommandReader::read_to_end(
  self : CommandReader,
) -> Bytes raise CommandError {
  let out = self.output.stdout[self.pos:].to_bytes()
  self.pos = self.output.stdout.length()
  self.eof = true
  self.close()
  out
}
