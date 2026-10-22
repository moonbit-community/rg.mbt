#!/usr/bin/env python3
"""Generate MoonBit WHATWG Encoding Standard tables for the searcher package.

Usage: scripts/gen_encodings.py <index-dir> [<out-dir>]

<index-dir> holds the official index files and encodings.json from
https://encoding.spec.whatwg.org/ (missing files are downloaded into it).
<out-dir> defaults to the `searcher` package directory. Run `moon fmt`
afterwards.

Two files are written:

* encoding_labels.mbt: the label -> encoding lookup (`encoding_kind_for_label`)
  and the names of the single-byte encodings.
* encoding_data.mbt: the decoding indexes, encoded as compact strings that are
  decoded lazily on first use (see encoding_index.mbt).

Numbers are written as variable-length base-32 sequences where characters in
'0'..'O' (0x30..0x4F) are continuation digits and 'P'..'o' (0x50..0x6F)
terminate a number (the same scheme as scripts/gen_unicode.py). Any other
character (e.g. the newlines of multi-line string literals) is ignored.

An index (pointer -> code point, with holes) is encoded as a sequence of
operations, each a number `payload << 2 | tag`, applied while tracking the
previous code point `prev` (initially `base`) and the current pointer:

  tag 0: a run of payload + 1 entries prev + 1, prev + 2, ...
  tag 1: skip payload + 1 pointers (no mapping)
  tag 2: one entry prev + payload + 2
  tag 3: one entry prev - payload

The gb18030 ranges index is encoded as (pointer delta, code point delta)
pairs.
"""
import json
import os
import sys
import urllib.request

BASE_URL = 'https://encoding.spec.whatwg.org/'

SINGLE_BYTE = [
    'IBM866', 'ISO-8859-2', 'ISO-8859-3', 'ISO-8859-4', 'ISO-8859-5',
    'ISO-8859-6', 'ISO-8859-7', 'ISO-8859-8', 'ISO-8859-8-I', 'ISO-8859-10',
    'ISO-8859-13',
    'ISO-8859-14', 'ISO-8859-15', 'ISO-8859-16', 'KOI8-R', 'KOI8-U',
    'macintosh', 'windows-874', 'windows-1250', 'windows-1251',
    'windows-1252', 'windows-1253', 'windows-1254', 'windows-1255',
    'windows-1256', 'windows-1257', 'windows-1258', 'x-mac-cyrillic',
]

# ISO-8859-8-I decodes exactly like ISO-8859-8 (it shares the index).
INDEX_FILE = {'ISO-8859-8-I': 'iso-8859-8'}

MULTI_BYTE = {
    'UTF-8': 'Utf8',
    'UTF-16LE': 'Utf16LE',
    'UTF-16BE': 'Utf16BE',
    'GBK': 'Gbk',
    'gb18030': 'Gb18030',
    'Big5': 'Big5',
    'EUC-JP': 'EucJp',
    'ISO-2022-JP': 'Iso2022Jp',
    'Shift_JIS': 'ShiftJis',
    'EUC-KR': 'EucKr',
    'x-user-defined': 'XUserDefined',
}

BIG_INDEXES = [
    ('jis0208', 'jis0208'),
    ('jis0212', 'jis0212'),
    ('euc-kr', 'euc_kr'),
    ('gb18030', 'gb18030'),
    ('big5', 'big5'),
]


def fetch(index_dir, fname):
    path = os.path.join(index_dir, fname)
    if not os.path.exists(path):
        os.makedirs(index_dir, exist_ok=True)
        with urllib.request.urlopen(BASE_URL + fname) as r:
            data = r.read()
        with open(path, 'wb') as f:
            f.write(data)
    return path


def load_index(index_dir, name):
    d = {}
    with open(fetch(index_dir, 'index-%s.txt' % name), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            d[int(parts[0])] = int(parts[1], 16)
    return d


def enc_num(n):
    assert n >= 0
    digits = []
    while True:
        digits.append(n & 31)
        n >>= 5
        if n == 0:
            break
    digits.reverse()
    s = ''.join(chr(0x30 + d) for d in digits[:-1])
    return s + chr(0x50 + digits[-1])


def enc_index(d, length, base):
    out = []
    prev = base
    i = 0
    while i < length:
        if i not in d:
            j = i
            while j < length and j not in d:
                j += 1
            if j == length:
                break
            out.append(enc_num(((j - i - 1) << 2) | 1))
            i = j
            continue
        c = d[i]
        if c == prev + 1:
            j = i
            while j < length and d.get(j) == prev + 1 + (j - i):
                j += 1
            out.append(enc_num(((j - i - 1) << 2) | 0))
            prev = d[j - 1]
            i = j
            continue
        if c > prev:
            out.append(enc_num(((c - prev - 2) << 2) | 2))
        else:
            out.append(enc_num(((prev - c) << 2) | 3))
        prev = c
        i += 1
    return ''.join(out)


def dec_index(s, length, base):
    """Reference decoder used to verify the encoding."""
    table = [None] * length
    prev = base
    i = 0
    n = 0
    for ch in s:
        c = ord(ch)
        if c < 0x30 or c > 0x6F:
            continue
        if c < 0x50:
            n = n * 32 + (c - 0x30)
            continue
        v = n * 32 + (c - 0x50)
        n = 0
        tag, payload = v & 3, v >> 2
        if tag == 0:
            for _ in range(payload + 1):
                prev += 1
                table[i] = prev
                i += 1
        elif tag == 1:
            i += payload + 1
        elif tag == 2:
            prev += payload + 2
            table[i] = prev
            i += 1
        else:
            prev -= payload
            table[i] = prev
            i += 1
    return table


def mbt_multiline(s, indent='  ', width=96):
    lines = [s[i:i + width] for i in range(0, len(s), width)] or ['']
    return '\n'.join('%s#|%s' % (indent, l) for l in lines)


def main():
    index_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'searcher')

    with open(fetch(index_dir, 'encodings.json'), encoding='utf-8') as f:
        groups = json.load(f)

    # Labels.
    arms = []
    for g in groups:
        for e in g['encodings']:
            name = e['name']
            if name == 'replacement':
                # Rejected, like encoding_rs's for_label_no_replacement.
                continue
            if name in MULTI_BYTE:
                kind = MULTI_BYTE[name]
            else:
                kind = 'SingleByte(%d)' % SINGLE_BYTE.index(name)
            arms.append((sorted(e['labels']), kind))
    known = set(SINGLE_BYTE) | set(MULTI_BYTE)
    for g in groups:
        for e in g['encodings']:
            assert e['name'] in known or e['name'] == 'replacement', e['name']

    with open(os.path.join(out_dir, 'encoding_labels.mbt'), 'w') as f:
        f.write('// Generated by scripts/gen_encodings.py. DO NOT EDIT.\n\n')
        f.write('///|\n/// Canonical names of the single-byte encodings, '
                'indexed like `single_byte_data`.\n')
        f.write('let single_byte_names : FixedArray[String] = [\n')
        for n in SINGLE_BYTE:
            f.write('  %s,\n' % json.dumps(n))
        f.write(']\n\n')
        f.write('///|\n/// Maps a trimmed, ASCII-lowercased WHATWG label to its '
                'encoding.\n/// Labels of the "replacement" encoding are not '
                'recognized.\n')
        f.write('fn encoding_kind_for_label(label : String) -> EncKind? {\n')
        f.write('  match label {\n')
        for labels, kind in arms:
            pats = ' | '.join(json.dumps(l) for l in labels)
            f.write('    %s => Some(%s)\n' % (pats, kind))
        f.write('    _ => None\n')
        f.write('  }\n}\n')

    # Indexes.
    sizes = {}
    with open(os.path.join(out_dir, 'encoding_data.mbt'), 'w') as f:
        f.write('// Generated by scripts/gen_encodings.py. DO NOT EDIT.\n')
        f.write('// Source: https://encoding.spec.whatwg.org/ index files.\n')
        for fname, ident in BIG_INDEXES:
            d = load_index(index_dir, fname)
            length = max(d) + 1
            s = enc_index(d, length, 0)
            dec = dec_index(s, length, 0)
            assert all(dec[p] == d.get(p) for p in range(length)), fname
            sizes[fname] = len(s)
            f.write('\n///|\nconst %s_LEN : Int = %d\n' % (ident.upper(), length))
            f.write('\n///|\n/// index-%s.txt (%d entries).\n' % (fname, len(d)))
            f.write('let %s_data : String =\n%s\n' % (ident, mbt_multiline(s)))

        # gb18030 ranges.
        pairs = sorted(load_index(index_dir, 'gb18030-ranges').items())
        out = []
        pp, pc = 0, 0
        for p, c in pairs:
            out.append(enc_num(p - pp))
            out.append(enc_num(c - pc))
            pp, pc = p, c
        s = ''.join(out)
        sizes['gb18030-ranges'] = len(s)
        f.write('\n///|\n/// index-gb18030-ranges.txt as (pointer delta, '
                'code point delta) pairs.\n')
        f.write('let gb18030_ranges_data : String =\n%s\n' % mbt_multiline(s))

        # Single-byte encodings: pointers 0..127 for bytes 0x80..0xFF.
        f.write('\n///|\n/// Single-byte indexes, indexed like '
                '`single_byte_names`. Entries start\n/// from a previous code '
                'point of 0x7F.\n')
        f.write('let single_byte_data : FixedArray[String] = [\n')
        total = 0
        for n in SINGLE_BYTE:
            d = load_index(index_dir, INDEX_FILE.get(n, n.lower()))
            s = enc_index(d, 128, 0x7F)
            dec = dec_index(s, 128, 0x7F)
            assert all(dec[p] == d.get(p) for p in range(128)), n
            total += len(s)
            f.write('  // %s\n  %s,\n' % (n, json.dumps(s)))
        f.write(']\n')
        sizes['single-byte'] = total
    for k, v in sizes.items():
        print('%-16s %7d chars' % (k, v))
    print('%-16s %7d chars' % ('total', sum(sizes.values())))


main()
