// Byte and substring search, vectorized with `moonbitlang/core/v128`.
//
// This is a pure MoonBit counterpart of the parts of Rust's `memchr` crate
// that ripgrep relies on. All functions search `hay[start:end]` and return
// absolute indices, or `-1` when there is no match.

///|
const LANES : Int32 = 16

///|
/// Returns the index of the first occurrence of `b` in `hay[start:end]`.
pub fn memchr(
  b : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let mut i = start
  if end - start >= LANES {
    let vb = @v128.i8x16_splat(b)
    while i + LANES <= end {
      let m = @v128.i8x16_bitmask(@v128.i8x16_eq(@v128.v128_load(hay, i), vb))
      if m != 0 {
        return i + m.ctz()
      }
      i += LANES
    }
  }
  while i < end {
    if hay[i] == b {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Returns the index of the first occurrence of `b1` or `b2`.
pub fn memchr2(
  b1 : Byte,
  b2 : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let mut i = start
  if end - start >= LANES {
    let v1 = @v128.i8x16_splat(b1)
    let v2 = @v128.i8x16_splat(b2)
    while i + LANES <= end {
      let chunk = @v128.v128_load(hay, i)
      let eq = @v128.v128_or_(
        @v128.i8x16_eq(chunk, v1),
        @v128.i8x16_eq(chunk, v2),
      )
      let m = @v128.i8x16_bitmask(eq)
      if m != 0 {
        return i + m.ctz()
      }
      i += LANES
    }
  }
  while i < end {
    let c = hay[i]
    if c == b1 || c == b2 {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Returns the index of the first occurrence of `b1`, `b2` or `b3`.
pub fn memchr3(
  b1 : Byte,
  b2 : Byte,
  b3 : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let mut i = start
  if end - start >= LANES {
    let v1 = @v128.i8x16_splat(b1)
    let v2 = @v128.i8x16_splat(b2)
    let v3 = @v128.i8x16_splat(b3)
    while i + LANES <= end {
      let chunk = @v128.v128_load(hay, i)
      let eq = @v128.v128_or_(
        @v128.v128_or_(@v128.i8x16_eq(chunk, v1), @v128.i8x16_eq(chunk, v2)),
        @v128.i8x16_eq(chunk, v3),
      )
      let m = @v128.i8x16_bitmask(eq)
      if m != 0 {
        return i + m.ctz()
      }
      i += LANES
    }
  }
  while i < end {
    let c = hay[i]
    if c == b1 || c == b2 || c == b3 {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Returns the index of the last occurrence of `b` in `hay[start:end]`.
pub fn memrchr(
  b : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let mut i = end
  if end - start >= LANES {
    let vb = @v128.i8x16_splat(b)
    while i - LANES >= start {
      let m = @v128.i8x16_bitmask(
        @v128.i8x16_eq(@v128.v128_load(hay, i - LANES), vb),
      )
      if m != 0 {
        return i - LANES + (31 - m.clz())
      }
      i -= LANES
    }
  }
  while i > start {
    i -= 1
    if hay[i] == b {
      return i
    }
  }
  -1
}

///|
/// Counts the occurrences of `b` in `hay[start:end]`.
pub fn count(
  b : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let mut n = 0
  let mut i = start
  if end - start >= LANES {
    let vb = @v128.i8x16_splat(b)
    while i + LANES <= end {
      let m = @v128.i8x16_bitmask(@v128.i8x16_eq(@v128.v128_load(hay, i), vb))
      n += m.popcnt()
      i += LANES
    }
  }
  while i < end {
    if hay[i] == b {
      n += 1
    }
    i += 1
  }
  n
}

///|
/// A substring searcher.
///
/// Candidates are found by checking two (preferably rare) bytes of the
/// needle at their offsets, 16 positions at a time, and then verified. This
/// is the "packed pair" algorithm used by Rust's `memchr::memmem`.
pub struct Finder {
  needle : FixedArray[Byte]
  i1 : Int32
  i2 : Int32
}

///|
/// Creates a finder for `needle` that filters candidates with the bytes at
/// offsets `i1` and `i2` (which should be the needle's rarest bytes). If
/// they are equal, the second offset is moved so the pair is distinct when
/// possible.
pub fn Finder::new(needle : FixedArray[Byte], i1 : Int32, i2 : Int32) -> Finder {
  let n = needle.length()
  let i1 = if n == 0 { 0 } else { i1 }
  let i2 = if n <= 1 {
    i1
  } else if i2 == i1 {
    if i1 + 1 < n {
      i1 + 1
    } else {
      i1 - 1
    }
  } else {
    i2
  }
  { needle, i1, i2, }
}

///|
pub fn Finder::needle(self : Finder) -> FixedArray[Byte] {
  self.needle
}

///|
fn Finder::verify(self : Finder, hay : FixedArray[Byte], at : Int32) -> Bool {
  let needle = self.needle
  for j in 0..<needle.length() {
    if hay[at + j] != needle[j] {
      return false
    }
  }
  true
}

///|
/// Returns the start of the first occurrence of the needle in
/// `hay[start:end]`.
pub fn Finder::find(
  self : Finder,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32 {
  let n = self.needle.length()
  if n == 0 {
    return if start <= end { start } else { -1 }
  }
  // Candidate starts are in `start..<limit`.
  let limit = end - n + 1
  if limit <= start {
    return -1
  }
  if n == 1 {
    return memchr(self.needle[0], hay, start, end)
  }
  let i1 = self.i1
  let i2 = self.i2
  let b1 = self.needle[i1]
  let b2 = self.needle[i2]
  let mut i = start
  if limit - start >= LANES {
    let v1 = @v128.i8x16_splat(b1)
    let v2 = @v128.i8x16_splat(b2)
    // Loads at `i + i1` and `i + i2` stay in bounds while `i + 16 <= limit`.
    while i + LANES <= limit {
      let eq = @v128.v128_and_(
        @v128.i8x16_eq(@v128.v128_load(hay, i + i1), v1),
        @v128.i8x16_eq(@v128.v128_load(hay, i + i2), v2),
      )
      let mut m = @v128.i8x16_bitmask(eq)
      while m != 0 {
        let at = i + m.ctz()
        if self.verify(hay, at) {
          return at
        }
        m = m & (m - 1)
      }
      i += LANES
    }
  }
  while i < limit {
    if hay[i + i1] == b1 && hay[i + i2] == b2 && self.verify(hay, i) {
      return i
    }
    i += 1
  }
  -1
}
