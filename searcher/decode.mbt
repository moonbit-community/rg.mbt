///|
priv enum EncKind {
  Utf8
  Utf16LE
  Utf16BE
  Windows1252
} derive(Eq)

///|
/// A character encoding used to transcode input to UTF-8 before searching.
pub struct Encoding {
  priv kind : EncKind
  priv name : String
}

///|
/// Looks up an encoding by its WHATWG label (case-insensitive). Only a
/// subset of encodings is supported: UTF-8, UTF-16LE, UTF-16BE and
/// windows-1252 (latin1).
pub fn Encoding::new(label : String) -> Encoding raise SearchError {
  let l = label.trim().to_lower().to_string()
  let kind = match l {
    "unicode-1-1-utf-8"
    | "unicode11utf8"
    | "unicode20utf8"
    | "utf-8"
    | "utf8"
    | "x-unicode20utf8" => Utf8
    "csunicode"
    | "iso-10646-ucs-2"
    | "ucs-2"
    | "unicode"
    | "unicodefeff"
    | "utf-16"
    | "utf-16le" => Utf16LE
    "unicodefffe" | "utf-16be" => Utf16BE
    "ansi_x3.4-1968"
    | "ascii"
    | "cp1252"
    | "cp819"
    | "csisolatin1"
    | "ibm819"
    | "iso-8859-1"
    | "iso-ir-100"
    | "iso8859-1"
    | "iso88591"
    | "iso_8859-1"
    | "iso_8859-1:1987"
    | "l1"
    | "latin1"
    | "us-ascii"
    | "windows-1252"
    | "x-cp1252" => Windows1252
    _ => raise ConfigError("grep config error: unknown encoding: \{label}")
  }
  let name = match kind {
    Utf8 => "UTF-8"
    Utf16LE => "UTF-16LE"
    Utf16BE => "UTF-16BE"
    Windows1252 => "windows-1252"
  }
  { kind, name, }
}

///|
pub fn Encoding::name(self : Encoding) -> String {
  self.name
}

///|
let windows1252_high : FixedArray[Int32] = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030,
  0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, 0x0090, 0x2018, 0x2019, 0x201C,
  0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D,
  0x017E, 0x0178,
]

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
    Windows1252 => {
      for i in self.raw_start..<self.raw_end {
        let b = self.raw[i].to_int()
        if b >= 0x80 && b < 0xA0 {
          push_char(out, windows1252_high[b - 0x80])
        } else {
          push_char(out, b)
        }
      }
      self.raw_start = self.raw_end
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
        if self.eof && self.raw_start >= self.raw_end {
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
