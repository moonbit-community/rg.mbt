///|
/// A prefilter quickly finds candidate match positions using literals that
/// every match must start with.
pub(all) enum Prefilter {
  /// A single byte.
  Byte(Int32)
  /// A set of bytes (each literal is a single byte).
  ByteSet(FixedArray[Bool])
  /// A single literal of length >= 2, with the offset of its rarest byte.
  Memmem(FixedArray[Byte], Int32)
  /// Several literals, bucketed by their first byte in priority order.
  Multi(FixedArray[Bool], Array[Array[FixedArray[Byte]]], Int32)
}

///|
/// Builds a prefilter from a set of literals, in priority order. Returns
/// `None` if no useful prefilter could be built.
pub fn Prefilter::new(lits : Array[Bytes]) -> Prefilter? {
  if lits.is_empty() || lits.iter().any(l => l.length() == 0) {
    return None
  }
  if lits.length() == 1 {
    let lit = lits[0]
    if lit.length() == 1 {
      return Some(Byte(lit[0].to_int()))
    }
    let mut rare = 0
    for i in 1..<lit.length() {
      if @syntax.rank(lit[i].to_int()) < @syntax.rank(lit[rare].to_int()) {
        rare = i
      }
    }
    return Some(Memmem(lit.to_fixedarray(), rare))
  }
  if lits.iter().all(l => l.length() == 1) {
    let set = FixedArray::make(256, false)
    for l in lits {
      set[l[0].to_int()] = true
    }
    return Some(ByteSet(set))
  }
  let set = FixedArray::make(256, false)
  let buckets : Array[Array[FixedArray[Byte]]] = Array::makei(256, _ => [])
  let mut min_len = lits[0].length()
  for l in lits {
    let b = l[0].to_int()
    set[b] = true
    buckets[b].push(l.to_fixedarray())
    if l.length() < min_len {
      min_len = l.length()
    }
  }
  Some(Multi(set, buckets, min_len))
}

///|
/// Returns true if the prefilter is believed to be fast.
pub fn Prefilter::is_fast(self : Prefilter) -> Bool {
  match self {
    Byte(b) => @syntax.rank(b) < 250
    ByteSet(set) => {
      let mut n = 0
      for b in set {
        if b {
          n += 1
        }
      }
      n <= 3
    }
    Memmem(_, _) => true
    Multi(set, _, _) => {
      let mut n = 0
      for i in 0..<256 {
        if set[i] {
          n += 1
        }
      }
      n <= 16
    }
  }
}

///|
/// Returns the position of the first byte equal to `b` in `hay[start:end]`.
pub fn memchr(
  b : Byte,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> Int32? {
  for i in start..<end {
    if hay[i] == b {
      return Some(i)
    }
  }
  None
}

///|
/// Returns true if `needle` occurs at `hay[at:]` (bounded by `end`).
fn matches_at(
  needle : FixedArray[Byte],
  hay : FixedArray[Byte],
  at : Int32,
  end : Int32,
) -> Bool {
  let n = needle.length()
  if at + n > end {
    return false
  }
  for j in 0..<n {
    if hay[at + j] != needle[j] {
      return false
    }
  }
  true
}

///|
/// Finds the start of the next candidate in `hay[start:end]`, returning
/// the span of the literal that was found (`(start, end)`).
pub fn Prefilter::find(
  self : Prefilter,
  hay : FixedArray[Byte],
  start : Int32,
  end : Int32,
) -> (Int32, Int32)? {
  match self {
    Byte(b) => {
      let b = b.to_byte()
      for i in start..<end {
        if hay[i] == b {
          return Some((i, i + 1))
        }
      }
      None
    }
    ByteSet(set) => {
      for i in start..<end {
        if set[hay[i].to_int()] {
          return Some((i, i + 1))
        }
      }
      None
    }
    Memmem(needle, rare) => {
      let n = needle.length()
      let rb = needle[rare]
      let mut i = start + rare
      let last = end - n + rare
      while i <= last {
        if hay[i] == rb {
          let s = i - rare
          if matches_at(needle, hay, s, end) {
            return Some((s, s + n))
          }
        }
        i += 1
      }
      None
    }
    Multi(set, buckets, min_len) => {
      let last = end - min_len
      for i in start..<=last {
        let b = hay[i].to_int()
        if set[b] {
          for lit in buckets[b] {
            if matches_at(lit, hay, i, end) {
              return Some((i, i + lit.length()))
            }
          }
        }
      }
      None
    }
  }
}
