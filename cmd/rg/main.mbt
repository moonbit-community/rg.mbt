///|
fn main {
  let args = @sys.args()
  let rest = if args.length() > 0 { args[1:].to_owned() } else { [] }
  let code = @core.run_main(rest)
  @sys.exit(code)
}
