///|
fn naive_find(
  hay : FixedArray[Byte],
  needle : FixedArray[Byte],
  s : Int32,
  e : Int32,
) -> Int32 {
  let n = needle.length()
  for i = s; i + n <= e; i = i + 1 {
    let mut ok = true
    for j in 0..<n {
      if hay[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
fn gen(len : Int32, seed : Int32) -> FixedArray[Byte] {
  let a = FixedArray::make(len, b'\x00')
  let mut x = seed.reinterpret_as_uint() + 12345
  for i in 0..<len {
    x = x * 1103515245 + 12345
    // A small alphabet makes matches and near-matches common.
    a[i] = (b'a'.to_int() + ((x >> 16) % 4).reinterpret_as_int()).to_byte()
  }
  a
}

///|
test "memchr family agrees with scalar search" {
  for len in [0, 1, 15, 16, 17, 31, 32, 33, 100, 257] {
    let hay = gen(len, len)
    for s in [0, 1, 3] {
      for e in [len, len - 1, len - 5] {
        if s > e || e < 0 {
          continue
        }
        for b in [b'a', b'b', b'd', b'z'] {
          let mut first = -1
          let mut last = -1
          let mut cnt = 0
          for i in s..<e {
            if hay[i] == b {
              if first < 0 {
                first = i
              }
              last = i
              cnt += 1
            }
          }
          assert_eq(@memchr.memchr(b, hay, s, e), first)
          assert_eq(@memchr.memrchr(b, hay, s, e), last)
          assert_eq(@memchr.count(b, hay, s, e), cnt)
          let mut f2 = -1
          let mut f3 = -1
          for i in s..<e {
            if f2 < 0 && (hay[i] == b || hay[i] == b'z') {
              f2 = i
            }
            if f3 < 0 && (hay[i] == b || hay[i] == b'z' || hay[i] == b'c') {
              f3 = i
            }
          }
          assert_eq(@memchr.memchr2(b, b'z', hay, s, e), f2)
          assert_eq(@memchr.memchr3(b, b'z', b'c', hay, s, e), f3)
        }
      }
    }
  }
}

///|
test "finder agrees with naive search" {
  for len in [0, 5, 16, 40, 200, 1000] {
    let hay = gen(len, len + 7)
    for nlen in [1, 2, 3, 5, 9, 20] {
      for off in [0, 3, 50] {
        if off + nlen > len {
          continue
        }
        let needle = FixedArray::make(nlen, b'\x00')
        for j in 0..<nlen {
          needle[j] = hay[off + j]
        }
        for (i1, i2) in [(0, nlen - 1), (nlen / 2, 0), (0, 0)] {
          let f = @memchr.Finder::new(needle, i1, i2)
          for s in [0, 2] {
            assert_eq(f.find(hay, s, len), naive_find(hay, needle, s, len))
          }
        }
      }
    }
  }
  // An absent needle.
  let hay = gen(500, 1)
  let f = @memchr.Finder::new([b'x', b'y', b'z'], 0, 2)
  assert_eq(f.find(hay, 0, 500), -1)
}
