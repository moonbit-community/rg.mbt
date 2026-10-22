// Reference outputs from encoding_rs for the searcher's decoder tests
// (searcher/decode_wbtest.mbt). Build it as src/main.rs of a throwaway cargo
// project depending on `encoding_rs = "=0.8.35"`.
//
// Usage:
//   encref hashes                      -- FNV-1a hashes of decoded test corpora
//                                         (the `encoding_rs_hashes` table)
//   encref decode <label> <hex bytes>  -- decoded output as \u escapes
//   encref dump <label> pairs|gb4|iso|random -- raw decoded corpus
use encoding_rs::Encoding;

fn fnv(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

fn corpus_pairs() -> Vec<u8> {
    let mut v = Vec::new();
    for a in 0..=255u8 {
        for b in 0..=255u8 {
            v.push(a);
            v.push(b);
            v.push(0x41);
        }
    }
    v
}

fn corpus_gb4() -> Vec<u8> {
    let mut v = Vec::new();
    for &b1 in &[0x81u8, 0x82, 0x84, 0x85, 0x8F, 0x90, 0x91, 0xE3, 0xE4, 0xFD, 0xFE] {
        for b2 in 0x30..=0x39u8 {
            for b3 in 0x81..=0xFEu8 {
                for b4 in 0x2F..=0x3Au8 {
                    v.extend_from_slice(&[b1, b2, b3, b4]);
                }
            }
        }
    }
    v
}

fn corpus_random(n: usize) -> Vec<u8> {
    let special = [0x1Bu8, 0x24, 0x28, 0x42, 0x40, 0x4A, 0x49, 0x0E, 0x0F, 0x5C, 0x7E, 0x8E, 0x8F, 0x80, 0x30, 0x39];
    let mut x: u64 = 0x9E3779B97F4A7C15;
    let mut v = Vec::with_capacity(n);
    for _ in 0..n {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let sel = (x >> 56) as u32;
        let r = ((x >> 40) & 0xFFFF) as u32;
        let b = if sel < 96 {
            (r & 0xFF) as u8
        } else if sel < 150 {
            (r % 0x80) as u8
        } else if sel < 190 {
            special[(r % 16) as usize]
        } else {
            (0x80 + r % 0x80) as u8
        };
        v.push(b);
    }
    v
}

fn corpus_iso(n: usize) -> Vec<u8> {
    let escapes: [&[u8]; 9] = [
        b"\x1B(B", b"\x1B(J", b"\x1B(I", b"\x1B$@", b"\x1B$B",
        b"\x1B", b"\x1B$", b"\x1B(", b"\x1B$A",
    ];
    let mut x: u64 = 0x2545F4914F6CDD1D;
    let mut v = Vec::new();
    for _ in 0..n {
        x = x
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let sel = (x >> 56) as u32;
        let r = ((x >> 40) & 0xFFFF) as u32;
        if sel < 30 {
            v.extend_from_slice(escapes[(r % 5) as usize]);
        } else if sel < 40 {
            v.extend_from_slice(escapes[5 + (r % 4) as usize]);
        } else if sel < 230 {
            v.push((0x21 + r % 0x5E) as u8);
        } else {
            v.push((r & 0xFF) as u8);
        }
    }
    v
}

fn decode(enc: &'static Encoding, input: &[u8]) -> Vec<u8> {
    let mut dec = enc.new_decoder_without_bom_handling();
    let mut out = vec![0u8; dec.max_utf8_buffer_length(input.len()).unwrap()];
    let (_, read, written, _) = dec.decode_to_utf8(input, &mut out, true);
    assert_eq!(read, input.len());
    out.truncate(written);
    out
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args[1] == "hashes" {
        let names = [
            "IBM866", "ISO-8859-2", "ISO-8859-3", "ISO-8859-4", "ISO-8859-5", "ISO-8859-6",
            "ISO-8859-7", "ISO-8859-8", "ISO-8859-8-I", "ISO-8859-10", "ISO-8859-13",
            "ISO-8859-14", "ISO-8859-15", "ISO-8859-16", "KOI8-R", "KOI8-U", "macintosh",
            "windows-874", "windows-1250", "windows-1251", "windows-1252", "windows-1253",
            "windows-1254", "windows-1255", "windows-1256", "windows-1257", "windows-1258",
            "x-mac-cyrillic", "GBK", "gb18030", "Big5", "EUC-JP", "ISO-2022-JP", "Shift_JIS",
            "EUC-KR", "UTF-16BE", "UTF-16LE", "x-user-defined",
        ];
        let pairs = corpus_pairs();
        let gb4 = corpus_gb4();
        let random = corpus_random(200_000);
        let iso = corpus_iso(100_000);
        for name in names.iter() {
            let enc = Encoding::for_label(name.as_bytes()).unwrap();
            assert_eq!(enc.name(), *name);
            println!(
                "    ({:?}, 0x{:016X}, 0x{:016X}, 0x{:016X}, 0x{:016X}, 0x{:016X}),",
                name,
                fnv(&decode(enc, &pairs)),
                fnv(&decode(enc, &gb4)),
                fnv(&decode(enc, &random)),
                fnv(&decode(enc, &random[..20_000])),
                fnv(&decode(enc, &iso)),
            );
        }
    } else if args[1] == "decode" {
        let enc = Encoding::for_label(args[2].as_bytes()).unwrap();
        let bytes: Vec<u8> = args[3..]
            .iter()
            .map(|h| u8::from_str_radix(h, 16).unwrap())
            .collect();
        let out = String::from_utf8(decode(enc, &bytes)).unwrap();
        let mut s = String::new();
        for c in out.chars() {
            if (c as u32) < 0x80 && c != '\\' && c != '"' && c >= ' ' {
                s.push(c);
            } else {
                s.push_str(&format!("\\u{{{:X}}}", c as u32));
            }
        }
        println!("{}", s);
    } else if args[1] == "dump" {
        // dump <label> <corpus> : write decoded bytes to stdout
        use std::io::Write;
        let enc = Encoding::for_label(args[2].as_bytes()).unwrap();
        let input = match args[3].as_str() {
            "pairs" => corpus_pairs(),
            "gb4" => corpus_gb4(),
            "iso" => corpus_iso(100_000),
            _ => corpus_random(200_000),
        };
        std::io::stdout().write_all(&decode(enc, &input)).unwrap();
    }
}
