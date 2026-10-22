///|
test "file times" {
  let t = @sys.file_times("moon.mod") catch {
    _ => return // unsupported on wasm
  }
  inspect(t.modified is Some(_), content="true")
}
