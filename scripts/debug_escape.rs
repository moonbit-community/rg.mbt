// Prints the ranges of chars that `{:?}` on a str escapes as \u{...}
// (excluding the named escapes \0 \t \n \r \" \\).
fn main() {
    let mut start: Option<u32> = None;
    let mut prev = 0u32;
    for cp in 0..=0x10FFFFu32 {
        let Some(c) = char::from_u32(cp) else { continue };
        let s = format!("{:?}", format!("a{}b", c));
        let escaped = s.contains("\\u{");
        if escaped {
            if start.is_none() { start = Some(cp); }
            prev = cp;
        } else if let Some(st) = start.take() {
            println!("{:X} {:X}", st, prev);
        }
        let _ = prev;
    }
    if let Some(st) = start { println!("{:X} {:X}", st, prev); }
}
