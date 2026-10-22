///|
/// A buffered writer to a file descriptor (stdout), implementing termcolor's
/// `Write`. Like grep-cli's `StandardStream`, it is either line buffered
/// (flushes after every newline) or block buffered.
pub struct StdoutWriter {
  priv fd : Int32
  priv buf : FixedArray[Byte]
  priv mut len : Int32
  priv line_buffered : Bool
}

///|
pub fn StdoutWriter::new(fd : Int32, line_buffered : Bool) -> StdoutWriter {
  { fd, buf: FixedArray::make(8192, b'\x00'), len: 0, line_buffered, }
}

///|
fn StdoutWriter::flush_buf(self : StdoutWriter) -> Unit raise @sys.IOError {
  if self.len > 0 {
    let n = self.len
    self.len = 0
    @sys.write_fd(self.fd, self.buf, 0, n)
  }
}

///|
pub impl @termcolor.Write for StdoutWriter with fn write_slice(
  self,
  data,
  start,
  end,
) {
  let len = end - start
  if len >= self.buf.length() {
    self.flush_buf()
    @sys.write_fd(self.fd, data, start, len)
    return
  }
  if self.len + len > self.buf.length() {
    self.flush_buf()
  }
  data.blit_to(self.buf, len~, src_offset=start, dst_offset=self.len)
  self.len += len
  if self.line_buffered {
    for i in start..<end {
      if data[i] == b'\n' {
        self.flush_buf()
        break
      }
    }
  }
}

///|
pub impl @termcolor.Write for StdoutWriter with fn flush(self) {
  self.flush_buf()
}
