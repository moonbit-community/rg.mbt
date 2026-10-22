///|
/// A parsed argument, like lexopt's `Arg`.
priv enum Arg {
  Short(Char)
  Long(String)
  Value(String)
}

///|
priv enum LexState {
  LNone
  PendingValue(String)
  Shorts(Array[Char], Int32)
  FinishedOpts
}

///|
/// A port of the `lexopt` argument lexer used by ripgrep.
priv struct Lexer {
  args : Array[String]
  mut idx : Int32
  mut state : LexState
  mut last_option : String?
}

///|
fn Lexer::new(args : Array[String]) -> Lexer {
  { args, idx: 0, state: LNone, last_option: None, }
}

///|
fn Lexer::next_source(self : Lexer) -> String? {
  if self.idx < self.args.length() {
    let a = self.args[self.idx]
    self.idx += 1
    Some(a)
  } else {
    None
  }
}

///|
/// Renders a value like Rust's `{:?}` for an `OsString`.
fn debug_os_string(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{0}' => buf.write_string("\\0")
      _ =>
        if c.to_int() < 0x20 || c.to_int() == 0x7F {
          buf.write_string("\\u{\{c.to_int().to_string(radix=16)}}")
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn Lexer::next(self : Lexer) -> Arg? raise RgError {
  match self.state {
    PendingValue(value) => {
      self.state = LNone
      raise RgError(
        "unexpected argument for option '\{self.last_option.unwrap()}': \{debug_os_string(value)}",
      )
    }
    Shorts(chars, pos) =>
      if pos >= chars.length() {
        self.state = LNone
      } else if chars[pos] == '=' && pos > 1 {
        let value = String::from_array(chars[pos + 1:])
        self.state = LNone
        raise RgError(
          "unexpected argument for option '\{self.last_option.unwrap()}': \{debug_os_string(value)}",
        )
      } else {
        let ch = chars[pos]
        self.state = Shorts(chars, pos + 1)
        self.last_option = Some("-\{ch}")
        return Some(Short(ch))
      }
    FinishedOpts =>
      return match self.next_source() {
        Some(a) => Some(Value(a))
        None => None
      }
    LNone => ()
  }
  guard self.next_source() is Some(arg) else { return None }
  if arg == "--" {
    self.state = FinishedOpts
    return self.next()
  }
  if arg.has_prefix("--") {
    let mut name = arg
    match arg.find("=") {
      Some(i) => {
        self.state = PendingValue(arg.view(start_offset=i + 1).to_owned())
        name = arg.view(end_offset=i).to_owned()
      }
      None => ()
    }
    self.last_option = Some(name)
    Some(Long(name.view(start_offset=2).to_owned()))
  } else if arg.length() > 1 && arg.has_prefix("-") {
    self.state = Shorts(arg.iter().collect(), 1)
    self.next()
  } else {
    Some(Value(arg))
  }
}

///|
fn Lexer::optional_value(self : Lexer) -> String? {
  match self.state {
    PendingValue(v) => {
      self.state = LNone
      Some(v)
    }
    Shorts(chars, pos) => {
      self.state = LNone
      if pos >= chars.length() {
        return None
      }
      let mut p = pos
      if chars[p] == '=' {
        p += 1
      }
      Some(String::from_array(chars[p:]))
    }
    FinishedOpts => None
    LNone => None
  }
}

///|
fn Lexer::value(self : Lexer) -> String raise RgError {
  if self.optional_value() is Some(v) {
    return v
  }
  if self.next_source() is Some(v) {
    return v
  }
  match self.last_option {
    Some(opt) => raise RgError("missing argument for option '\{opt}'")
    None => raise RgError("missing argument")
  }
}
