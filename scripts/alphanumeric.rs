// Prints the ranges of chars for which `char::is_alphanumeric` is true.
fn main() {
    let mut start: Option<u32> = None;
    let mut prev = 0u32;
    for cp in 0..=0x10FFFFu32 {
        let Some(c) = char::from_u32(cp) else { continue };
        if c.is_alphanumeric() {
            if start.is_none() { start = Some(cp); }
            prev = cp;
        } else if let Some(st) = start.take() {
            println!("{:X} {:X}", st, prev);
        }
    }
    if let Some(st) = start { println!("{:X} {:X}", st, prev); }
}
