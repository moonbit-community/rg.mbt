///|
/// A tiny command line exercising `dii/rg/sys`:
///
/// ```text
/// demo args               print the arguments
/// demo info               cwd, hostname, tty and stdin state, clock
/// demo env NAME           print an environment variable
/// demo ls DIR             list a directory with file types
/// demo stat PATH          metadata and symlink_metadata of PATH
/// demo cat FILE...        copy files to stdout
/// demo stdin              copy stdin to stdout
/// demo run PROG ARGS...   run a program and show its output
/// ```
fn main {
  let args = @sys.args()
  let cmd = if args.length() > 1 { args[1] } else { "args" }
  let rest = args[2:].to_owned()
  run(cmd, rest) catch {
    e => {
      eprint("demo: \{e}\n")
      @sys.exit(1)
    }
  }
}

///|
fn print(s : String) -> Unit raise @sys.IOError {
  let b = @utf8.encode(s)
  let buf : FixedArray[Byte] = FixedArray::make(b.length(), 0)
  buf.blit_from_bytes(0, b, 0, b.length())
  @sys.write_fd(1, buf, 0, buf.length())
}

///|
fn eprint(s : String) -> Unit {
  let b = @utf8.encode(s)
  let buf : FixedArray[Byte] = FixedArray::make(b.length(), 0)
  buf.blit_from_bytes(0, b, 0, b.length())
  @sys.write_fd(2, buf, 0, buf.length()) catch {
    _ => ()
  }
}

///|
fn type_name(t : @sys.FileType?) -> String {
  match t {
    Some(File) => "file"
    Some(Dir) => "dir"
    Some(Symlink) => "symlink"
    Some(Other) => "other"
    None => "unknown"
  }
}

///|
fn copy_fd(fd : Int32) -> Int32 raise @sys.IOError {
  let buf : FixedArray[Byte] = FixedArray::make(8192, 0)
  let mut total = 0
  for ;; {
    let n = @sys.read_fd(fd, buf, 0, buf.length())
    if n == 0 {
      break
    }
    @sys.write_fd(1, buf, 0, n)
    total += n
  }
  total
}

///|
fn run(cmd : String, rest : Array[String]) -> Unit raise @sys.IOError {
  match cmd {
    "args" =>
      for i, a in @sys.args() {
        print("arg[\{i}] = \{a}\n")
      }
    "info" => {
      print("current_dir = \{Repr(@sys.current_dir())}\n")
      print("hostname = \{Repr(@sys.hostname())}\n")
      print("is_windows = \{@sys.is_windows()}\n")
      print(
        "is_tty(0,1,2) = \{@sys.is_tty(0)},\{@sys.is_tty(1)},\{@sys.is_tty(2)}\n",
      )
      print("stdin_is_readable = \{@sys.stdin_is_readable()}\n")
      print("now_nanos > 0 = \{@sys.now_nanos() > 0}\n")
      print("env_vars count = \{@sys.env_vars().length()}\n")
    }
    "env" =>
      for name in rest {
        print("\{name} = \{Repr(@sys.env_var(name))}\n")
      }
    "ls" => {
      let dir = if rest.is_empty() { "." } else { rest[0] }
      let entries = @sys.read_dir(dir)
      for e in entries {
        print("\{type_name(e.file_type)}\t\{e.name}\n")
      }
    }
    "stat" =>
      for p in rest {
        let md = @sys.metadata(p) catch {
          e => {
            print("\{p}: metadata error: \{e}\n")
            continue
          }
        }
        print(
          "\{p}: metadata: \{type_name(Some(md.file_type))} len=\{md.len} dev=\{md.dev} ino=\{md.ino}\n",
        )
        let lmd = @sys.symlink_metadata(p)
        print(
          "\{p}: symlink_metadata: \{type_name(Some(lmd.file_type))} len=\{lmd.len}\n",
        )
        if lmd.file_type is Symlink {
          print("\{p}: -> \{@sys.read_link(p)}\n")
        }
      }
    "cat" =>
      for p in rest {
        let f = @sys.File::open(p)
        defer f.close()
        ignore(copy_fd(f.fd()))
      }
    "stdin" => {
      let n = copy_fd(0)
      eprint("[read \{n} bytes from stdin]\n")
    }
    "run" => {
      guard !rest.is_empty() else {
        raise @sys.IOError::other(InvalidInput, "usage: demo run PROG ARGS...")
      }
      let out = @sys.run_command(rest[0], rest[1:].to_owned())
      print("status = \{out.status}\n")
      print("stdout = \{@utf8.decode_lossy(out.stdout)}")
      print("stderr = \{@utf8.decode_lossy(out.stderr)}")
    }
    _ => raise @sys.IOError::other(InvalidInput, "unknown command: \{cmd}")
  }
}
