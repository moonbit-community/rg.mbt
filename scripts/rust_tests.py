"""Helpers for converting Rust test code into MoonBit."""
import re


def parse_rust_string(src, i):
    """Parses a Rust string literal starting at src[i]. Returns (value, end)."""
    if src.startswith('r#"', i):
        j = src.index('"#', i + 3)
        return src[i + 3:j], j + 2
    if src.startswith('r"', i):
        j = src.index('"', i + 2)
        return src[i + 2:j], j + 1
    if src.startswith('b"', i):
        i += 1
    assert src[i] == '"', src[i:i + 20]
    out = []
    j = i + 1
    while True:
        c = src[j]
        if c == '"':
            return ''.join(out), j + 1
        if c == '\\':
            n = src[j + 1]
            if n == '\n':
                j += 2
                while src[j] in ' \t\n\r':
                    j += 1
                continue
            m = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '0': '\0',
                 '"': '"', "'": "'"}
            if n in m:
                out.append(m[n])
                j += 2
                continue
            if n == 'x':
                out.append(chr(int(src[j + 2:j + 4], 16)))
                j += 4
                continue
            if n == 'u':
                k = src.index('}', j)
                out.append(chr(int(src[j + 3:k], 16)))
                j = k + 1
                continue
            raise Exception('bad escape ' + n)
        out.append(c)
        j += 1


def mbt_str(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif o < 0x20 or o == 0x7f:
            out.append('\\u{%x}' % o)
        else:
            out.append(ch)
    return '"' + ''.join(out) + '"'


def convert_strings(src):
    """Replaces every Rust string literal in src with a MoonBit literal."""
    out = []
    i = 0
    while i < len(src):
        c = src[i]
        if c == '"' or src.startswith('r"', i) or src.startswith('r#"', i) or (src.startswith('b"', i) and not src[i-1:i].isalnum()):
            if (c == 'r' or c == 'b') and i > 0 and (src[i - 1].isalnum() or src[i-1] == '_'):
                out.append(c)
                i += 1
                continue
            v, j = parse_rust_string(src, i)
            out.append(mbt_str(v))
            i = j
            continue
        if c == "'" and i + 2 < len(src) and (src[i + 2] == "'" or src[i + 1] == '\\'):
            # char literal; copy through
            j = src.index("'", i + 2)
            out.append(src[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def extract_tests(src):
    """Yields (name, body) of each #[test] fn in src."""
    for m in re.finditer(r'#\[test\]\s*(?:#\[[^\]]*\]\s*)*fn (\w+)\(\) \{', src):
        start = m.end()
        depth = 1
        i = start
        while depth:
            c = src[i]
            if c == '"' or src.startswith('r"', i):
                if c == 'r' and src[i - 1].isalnum():
                    i += 1
                    continue
                _, i = parse_rust_string(src, i)
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        yield m.group(1), src[start:i - 1]
