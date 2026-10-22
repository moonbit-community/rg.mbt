///|
/// The decoder family of an encoding.
priv enum EncKind {
  Utf8
  Utf16LE
  Utf16BE
  /// A single-byte encoding, indexing `single_byte_names`.
  SingleByte(Int32)
  Gbk
  Gb18030
  Big5
  EucJp
  Iso2022Jp
  ShiftJis
  EucKr
  XUserDefined
} derive(Eq)

///|
/// The canonical WHATWG name of the encoding.
fn EncKind::name(self : EncKind) -> String {
  match self {
    Utf8 => "UTF-8"
    Utf16LE => "UTF-16LE"
    Utf16BE => "UTF-16BE"
    SingleByte(i) => single_byte_names[i]
    Gbk => "GBK"
    Gb18030 => "gb18030"
    Big5 => "Big5"
    EucJp => "EUC-JP"
    Iso2022Jp => "ISO-2022-JP"
    ShiftJis => "Shift_JIS"
    EucKr => "EUC-KR"
    XUserDefined => "x-user-defined"
  }
}

///|
/// A character encoding used to transcode input to UTF-8 before searching.
pub struct Encoding {
  priv kind : EncKind
  priv name : String
}

///|
fn is_ascii_whitespace(c : UInt16) -> Bool {
  c is ('\t' | '\n' | '\u{0C}' | '\r' | ' ')
}

///|
/// Implements the Encoding Standard's "get an encoding" for `label`: leading
/// and trailing ASCII whitespace is removed and the label is matched ASCII
/// case-insensitively.
fn lookup_label(label : String) -> EncKind? {
  let mut start = 0
  let mut end = label.length()
  while start < end && is_ascii_whitespace(label[start]) {
    start += 1
  }
  while end > start && is_ascii_whitespace(label[end - 1]) {
    end -= 1
  }
  let sb = StringBuilder()
  for i in start..<end {
    let c = label[i].to_int()
    if c >= 0x80 {
      // All labels are ASCII.
      return None
    }
    let c = if c >= 'A'.to_int() && c <= 'Z'.to_int() { c + 0x20 } else { c }
    sb.write_char(c.unsafe_to_char())
  }
  encoding_kind_for_label(sb.to_string())
}

///|
/// Looks up an encoding by its WHATWG label, like encoding_rs's
/// `Encoding::for_label_no_replacement`: every label of the Encoding Standard
/// is accepted (ASCII case-insensitively, ignoring surrounding ASCII
/// whitespace) except those of the "replacement" encoding.
pub fn Encoding::new(label : String) -> Encoding raise SearchError {
  guard lookup_label(label) is Some(kind) else {
    raise ConfigError("grep config error: unknown encoding: \{label}")
  }
  { kind, name: kind.name(), }
}

///|
/// Returns the canonical WHATWG name of the encoding, e.g. `Shift_JIS`.
pub fn Encoding::name(self : Encoding) -> String {
  self.name
}

///|
/// Returns the encoding indicated by a byte order mark at the start of
/// `buf[start:end]`, along with the BOM length.
fn sniff_bom(
  buf : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> (EncKind, Int32)? {
  let n = end - start
  if n >= 3 &&
    buf[start] == b'\xEF' &&
    buf[start + 1] == b'\xBB' &&
    buf[start + 2] == b'\xBF' {
    Some((Utf8, 3))
  } else if n >= 2 && buf[start] == b'\xFF' && buf[start + 1] == b'\xFE' {
    Some((Utf16LE, 2))
  } else if n >= 2 && buf[start] == b'\xFE' && buf[start + 1] == b'\xFF' {
    Some((Utf16BE, 2))
  } else {
    None
  }
}

///|
/// Returns true if the slice begins with a UTF-8 or UTF-16 BOM.
pub fn slice_has_bom(
  buf : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Bool {
  sniff_bom(buf, start, end) is Some(_)
}

///|
/// A reader that sniffs a BOM and transcodes its input to UTF-8.
priv struct DecodeReader {
  inner : &Reader
  encoding : EncKind?
  bom_sniffing : Bool
  mut started : Bool
  mut mode : EncKind?
  // Raw input waiting to be decoded.
  raw : FixedArray[Byte]
  mut raw_start : Int32
  mut raw_end : Int32
  mut eof : Bool
  // State of the legacy decoder, if `mode` needs one.
  mut legacy : LegacyDecoder?
  // Whether the end of the input has been fully decoded.
  mut flushed : Bool
  // Decoded output waiting to be returned.
  out : Buffer
  mut out_pos : Int32
  mut out_bytes : Bytes
}

///|
fn DecodeReader::new(
  inner : &Reader,
  encoding : EncKind?,
  bom_sniffing : Bool,
) -> DecodeReader {
  {
    inner,
    encoding,
    bom_sniffing,
    started: false,
    mode: None,
    raw: FixedArray::make(8192, b'\x00'),
    raw_start: 0,
    raw_end: 0,
    eof: false,
    legacy: None,
    flushed: false,
    out: Buffer(),
    out_pos: 0,
    out_bytes: b"",
  }
}

///|
fn DecodeReader::fill_raw(self : DecodeReader) -> Unit raise {
  if self.eof {
    return
  }
  if self.raw_start > 0 {
    let n = self.raw_end - self.raw_start
    self.raw.blit_to(self.raw, len=n, src_offset=self.raw_start, dst_offset=0)
    self.raw_start = 0
    self.raw_end = n
  }
  let n = self.inner.read(
    self.raw,
    self.raw_end,
    self.raw.length() - self.raw_end,
  )
  if n == 0 {
    self.eof = true
  } else {
    self.raw_end += n
  }
}

///|
fn DecodeReader::start(self : DecodeReader) -> Unit raise {
  self.started = true
  if self.bom_sniffing {
    // Read exactly 3 bytes (or until EOF) to sniff a BOM, just like
    // encoding_rs_io's BOM peeker. The peeked bytes are returned by the
    // first read on their own.
    while self.raw_end < 3 && !self.eof {
      let n = self.inner.read(self.raw, self.raw_end, 3 - self.raw_end)
      if n == 0 {
        self.eof = true
      } else {
        self.raw_end += n
      }
    }
    if sniff_bom(self.raw, self.raw_start, self.raw_end) is Some((kind, len)) {
      self.raw_start += len
      self.mode = Some(kind)
      return
    }
  }
  self.mode = self.encoding
  match self.encoding {
    None | Some(Utf8 | Utf16LE | Utf16BE) => ()
    Some(kind) => self.legacy = Some(LegacyDecoder::new(kind))
  }
}

///|
fn push_char(out : Buffer, c : Int32) -> Unit {
  if c < 0x80 {
    out.write_byte(c.to_byte())
  } else if c < 0x800 {
    out.write_byte((0xC0 | (c >> 6)).to_byte())
    out.write_byte((0x80 | (c & 0x3F)).to_byte())
  } else if c < 0x10000 {
    out.write_byte((0xE0 | (c >> 12)).to_byte())
    out.write_byte((0x80 | ((c >> 6) & 0x3F)).to_byte())
    out.write_byte((0x80 | (c & 0x3F)).to_byte())
  } else {
    out.write_byte((0xF0 | (c >> 18)).to_byte())
    out.write_byte((0x80 | ((c >> 12) & 0x3F)).to_byte())
    out.write_byte((0x80 | ((c >> 6) & 0x3F)).to_byte())
    out.write_byte((0x80 | (c & 0x3F)).to_byte())
  }
}

///|
/// Decodes as much buffered raw input as possible into `self.out`.
fn DecodeReader::decode_some(self : DecodeReader, kind : EncKind) -> Unit {
  let out = self.out
  match kind {
    Utf8 => ()
    SingleByte(_)
    | Gbk
    | Gb18030
    | Big5
    | EucJp
    | Iso2022Jp
    | ShiftJis
    | EucKr
    | XUserDefined => {
      if self.legacy is Some(dec) {
        dec.feed(self.raw, self.raw_start, self.raw_end, out)
        if self.eof {
          dec.finish(out)
        }
      }
      self.raw_start = self.raw_end
      if self.eof {
        self.flushed = true
      }
    }
    Utf16LE | Utf16BE => {
      let le = kind == Utf16LE
      let unit = (i : Int32) => {
        if le {
          self.raw[i].to_int() | (self.raw[i + 1].to_int() << 8)
        } else {
          (self.raw[i].to_int() << 8) | self.raw[i + 1].to_int()
        }
      }
      let mut i = self.raw_start
      while i + 1 < self.raw_end {
        let u = unit(i)
        if u >= 0xD800 && u <= 0xDBFF {
          if i + 3 < self.raw_end {
            let u2 = unit(i + 2)
            if u2 >= 0xDC00 && u2 <= 0xDFFF {
              push_char(out, 0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00))
              i += 4
            } else {
              push_char(out, 0xFFFD)
              i += 2
            }
          } else if self.eof {
            push_char(out, 0xFFFD)
            i += 2
          } else {
            break
          }
        } else if u >= 0xDC00 && u <= 0xDFFF {
          push_char(out, 0xFFFD)
          i += 2
        } else {
          push_char(out, u)
          i += 2
        }
      }
      if self.eof && i < self.raw_end {
        // A dangling odd byte.
        push_char(out, 0xFFFD)
        i = self.raw_end
      }
      self.raw_start = i
      if self.eof {
        self.flushed = true
      }
    }
  }
}

///|
impl Reader for DecodeReader with fn read(self, buf, start, len) {
  if !self.started {
    self.start()
  }
  match self.mode {
    None | Some(Utf8) => {
      // Pass through, first draining any sniffed bytes.
      if self.raw_start < self.raw_end {
        let n = if self.raw_end - self.raw_start < len {
          self.raw_end - self.raw_start
        } else {
          len
        }
        self.raw.blit_to(
          buf,
          len=n,
          src_offset=self.raw_start,
          dst_offset=start,
        )
        self.raw_start += n
        return n
      }
      if self.eof {
        return 0
      }
      self.inner.read(buf, start, len)
    }
    Some(kind) => {
      while self.out_pos >= self.out_bytes.length() {
        if self.flushed {
          return 0
        }
        self.fill_raw()
        self.out.reset()
        self.decode_some(kind)
        self.out_bytes = self.out.to_bytes()
        self.out_pos = 0
      }
      let avail = self.out_bytes.length() - self.out_pos
      let n = if avail < len { avail } else { len }
      buf.blit_from_bytes(start, self.out_bytes, self.out_pos, n)
      self.out_pos += n
      n
    }
  }
}
