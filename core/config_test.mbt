///|
test "config basic" {
  let (args, errs) = @core.parse_config_bytes(
    b"# Test\n--context=0\n   --smart-case\n-u\n\n   # --bar\n--foo\n",
  )
  inspect(errs.is_empty(), content="true")
  debug_inspect(
    args,
    content=(
      #|["--context=0", "--smart-case", "-u", "--foo"]
    ),
  )
}

///|
test "config error" {
  let (args, errs) = @core.parse_config_bytes(b"quux\nfoo\xFFbar\nbaz\n")
  debug_inspect(
    args,
    content=(
      #|["quux", "foo�bar", "baz"]
    ),
  )
  inspect(errs.length(), content="0")
}
