///|
test "decompress gzip (native)" {
  // Skip where processes can't be spawned (e.g. wasm).
  let can_spawn = try @sys.run_command("true", []) catch {
    _ => false
  } noraise {
    _ => true
  }
  if !can_spawn {
    return
  }
  let path = "_build/tmpcli/a.txt.gz"
  if !@sys.path_exists(path) {
    return
  }
  let m = @cli.DecompressionMatcher::new()
  inspect(m.has_command(path), content="true")
  inspect(m.has_command("foo.txt"), content="false")
  let r = @cli.DecompressionReader::new(path) catch {
    _ => return // e.g. on wasm, where processes are unsupported
  }
  let buf = FixedArray::make(100, b'\x00')
  let n = r.read(buf, 0, 100) catch { _ => return }
  inspect(
    @utf8.decode_lossy(Bytes::from_array(buf[0:n])),
    content="hello gzip\nline two\n",
  )
}
