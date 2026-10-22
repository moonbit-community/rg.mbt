#!/usr/bin/env python3
"""Mechanically converts grep-printer Rust unit tests to MoonBit.

This was used to produce standard_test.mbt and summary_test.mbt from the
`#[cfg(test)]` modules of grep-printer's standard.rs and summary.rs:

  python3 convert_rust_tests.py standard.rs 1744 std_header.mbt out.mbt \
      reports_stats,reports_stats_multiple
  python3 convert_rust_tests.py summary.rs 791 summary_header.mbt out.mbt \
      path_with_match_error,path_without_match_error

followed by `moon fmt`. Skipped tests were ported by hand (they inspect
timings or errors), and a few conversions were touched up by hand (e.g.
`sink.match_count` -> `sink.match_count()`, `SHERLOCK` -> `summary_sherlock`
for the summary tests). Expected output strings are copied verbatim.
"""
import re, sys

def find_tests(src):
    """Yield (name, body) for each #[test] fn in src."""
    out = []
    for m in re.finditer(r'#\[test\]\s*\n\s*fn (\w+)\(\) \{', src):
        i = m.end()
        depth = 1
        j = i
        # naive brace matching that skips string literals
        while depth > 0:
            c = src[j]
            if c == '"':
                j = skip_str(src, j)
                continue
            if c == "'" and src[j+1:j+2] != '' :
                # char literal like '\x00' or 'a' or lifetime; try skip
                mm = re.match(r"'(\\x[0-9a-fA-F]{2}|\\.|[^'\\])'", src[j:])
                if mm:
                    j += mm.end()
                    continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            j += 1
        out.append((m.group(1), src[i:j-1]))
    return out

def skip_str(src, j):
    # j at opening quote
    k = j + 1
    while src[k] != '"':
        if src[k] == '\\':
            k += 2
        else:
            k += 1
    return k + 1

def rust_unescape(s):
    """Unescape the contents of a normal Rust string literal."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c != '\\':
            out.append(c); i += 1; continue
        n = s[i+1]
        if n == '\n':
            i += 2
            while i < len(s) and s[i] in ' \t\n\r':
                i += 1
            continue
        if n == 'n': out.append('\n'); i += 2
        elif n == 'r': out.append('\r'); i += 2
        elif n == 't': out.append('\t'); i += 2
        elif n == '0': out.append('\0'); i += 2
        elif n == '\\': out.append('\\'); i += 2
        elif n == '"': out.append('"'); i += 2
        elif n == "'": out.append("'"); i += 2
        elif n == 'x':
            out.append(chr(int(s[i+2:i+4], 16))); i += 4
        elif n == 'u':
            k = s.index('}', i)
            out.append(chr(int(s[i+3:k], 16))); i = k + 1
        else:
            raise Exception("bad escape " + n)
    return ''.join(out)

def mbt_str(v, indent):
    """Emit a MoonBit string expression for python string v."""
    printable = all((c == '\n') or (0x20 <= ord(c) < 0x7f) or ord(c) >= 0xa0 for c in v)
    if '\n' in v and printable:
        lines = v.split('\n')
        pad = ' ' * indent
        return '(\n' + '\n'.join(pad + '#|' + l for l in lines) + '\n' + pad[:-2] + ')'
    res = []
    for c in v:
        if c == '\n': res.append('\\n')
        elif c == '\r': res.append('\\r')
        elif c == '\t': res.append('\\t')
        elif c == '\\': res.append('\\\\')
        elif c == '"': res.append('\\"')
        elif ord(c) < 0x20 or ord(c) == 0x7f: res.append('\\u{%x}' % ord(c))
        else: res.append(c)
    return '"' + ''.join(res) + '"'

def mbt_bytes(v):
    res = []
    for c in v:
        o = ord(c)
        if c == '\n': res.append('\\n')
        elif c == '\r': res.append('\\r')
        elif c == '\t': res.append('\\t')
        elif c == '\\': res.append('\\\\')
        elif c == '"': res.append('\\"')
        elif o < 0x20 or o >= 0x7f: res.append('\\x%02x' % o)
        else: res.append(c)
    return 'b"' + ''.join(res) + '"'

def tokenize_strings(body):
    """Replace string literals with placeholders. Returns (code, strs)."""
    strs = []
    out = []
    i = 0
    while i < len(body):
        m = re.match(r'(b?)r(#*)"', body[i:])
        if m and (i == 0 or not (body[i-1].isalnum() or body[i-1] == '_')):
            hashes = m.group(2)
            start = i + m.end()
            end = body.index('"' + hashes, start)
            val = body[start:end]
            strs.append(('bytes' if m.group(1) else 'str', val))
            out.append('__STR%d__' % (len(strs) - 1))
            i = end + 1 + len(hashes)
            continue
        m = re.match(r'b"', body[i:])
        if m and (i == 0 or not (body[i-1].isalnum() or body[i-1] == '_')):
            j = skip_str(body, i + 1)
            strs.append(('bytes', rust_unescape(body[i+2:j-1])))
            out.append('__STR%d__' % (len(strs) - 1))
            i = j
            continue
        if body[i] == '"':
            j = skip_str(body, i)
            strs.append(('str', rust_unescape(body[i+1:j-1])))
            out.append('__STR%d__' % (len(strs) - 1))
            i = j
            continue
        out.append(body[i])
        i += 1
    return ''.join(out), strs

def split_statements(code):
    """Split code at top-level ';'."""
    stmts = []
    depth = 0
    cur = []
    for c in code:
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ';' and depth == 0:
            stmts.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(c)
    rest = ''.join(cur).strip()
    if rest:
        stmts.append(rest)
    return stmts

PRINTER_TYPES = ['StandardBuilder', 'ColorSpecs', 'UserColorSpec', 'SummaryBuilder',
                 'SummaryKind', 'JSONBuilder', 'Standard', 'Summary']

def convert_code(s):
    s = re.sub(r'\.unwrap\(\)', lambda m: m.group(0), s)
    # remove unwrap except after stats()
    s = re.sub(r'(?<!stats\(\))\s*\.unwrap\(\)', '', s)
    s = re.sub(r'\blet mut\b', 'let', s)
    s = re.sub(r'&mut\s+', '', s)
    s = re.sub(r'&matcher\b', 'matcher', s)
    s = re.sub(r'\bRegexMatcherBuilder::new\(\)', '@grep_regex.RegexMatcherBuilder::new()', s)
    s = re.sub(r'\bRegexMatcher::new\(', '@grep_regex.RegexMatcher::new(', s)
    s = re.sub(r'\bSearcherBuilder::new\(\)', '@searcher.SearcherBuilder::new()', s)
    s = re.sub(r'\bBinaryDetection::quit\(', '@searcher.BinaryDetection::BinaryQuit(', s)
    s = re.sub(r'\bBinaryDetection::convert\(', '@searcher.BinaryDetection::BinaryConvert(', s)
    s = re.sub(r'\bLineTerminator::', '@matcher.LineTerminator::', s)
    for t in PRINTER_TYPES:
        s = re.sub(r'(?<![@.\w])' + t + r'::', '@printer.' + t + '::', s)
    s = re.sub(r'NoColor::new\(vec!\[\]\)', '@termcolor.NoColor::new(out)', s)
    s = re.sub(r'Ansi::new\(vec!\[\]\)', '@termcolor.Ansi::new(out)', s)
    s = re.sub(r'build_no_color\(vec!\[\]\)', 'build_no_color(out)', s)
    s = re.sub(r'\.build\(vec!\[\]\)', '.build(out)', s)
    s = re.sub(r'(__STR\d+__)\.to_vec\(\)', r'\1', s)
    s = re.sub(r'(__STR\d+__)\.parse\(\)', r'@printer.UserColorSpec::parse(\1)', s)
    s = re.sub(r'@printer\.ColorSpecs::new\(&\[', '@printer.ColorSpecs::new([', s)
    s = re.sub(r'printer_contents(_ansi)?\(printer\)', 'contents(out)', s)
    s = re.sub(r'&(__STR\d+__)\[\.\.\]', r'\1', s)
    s = re.sub(r'(\w+|__STR\d+__)\.as_bytes\(\)', r'str_bytes(\1)', s)
    s = re.sub(r'\.search_reader\(\s*matcher,\s*', '.search_reader(\n  matcher,\n  __RDR__(', s)
    s = re.sub(r'\.search_slice\(\s*matcher,\s*', '.search_bytes(\n  matcher,\n  __SLC__(', s)
    s = re.sub(r'\bSHERLOCK_CRLF\b', 'sherlock_crlf', s)
    s = re.sub(r'\bSHERLOCK\b', 'sherlock', s)
    s = re.sub(r'assert_eq_printed!\((\w+|__STR\d+__),\s*(\w+)\)', r'assert_eq(\2, \1)', s)
    s = re.sub(r'assert_eq!\(', 'assert_eq(', s)
    s = re.sub(r'assert!\(([\w.]+\(\))\.is_none\(\)\)', r'assert_true(\1 is None)', s)
    s = re.sub(r'assert!\(!', 'assert_false(', s)
    s = re.sub(r'assert!\(', 'assert_true(', s)
    return s

def fix_reader_args(s):
    """After inserting 'reader(' we need to close it before the sink arg."""
    out = []
    i = 0
    while True:
        k = s.find('__RDR__(', i)
        k2 = s.find('__SLC__(', i)
        cands = [x for x in [k, k2] if x != -1]
        if not cands:
            out.append(s[i:]); break
        k = min(cands)
        tok = '__RDR__(' if s.startswith('__RDR__(', k) else '__SLC__('
        # make sure it's our inserted token (preceded by newline + spaces)
        out.append(s[i:k+len(tok)])
        j = k + len(tok)
        # read the argument until top-level comma
        depth = 0
        while True:
            c = s[j]
            if c in '([{': depth += 1
            if c in ')]}': depth -= 1
            if c == ',' and depth == 0:
                break
            j += 1
        out.append(s[k+len(tok):j].strip() + ')')
        i = j
    return ''.join(out)

def emit_test(name, body, indent=2):
    code, strs = tokenize_strings(body)
    lines = []
    for st in split_statements(code):
        if st.startswith('use ') or not st:
            continue
        st = convert_code(st)
        if '__RDR__(' in st or '__SLC__(' in st:
            st = fix_reader_args(st)
            st = st.replace('__RDR__(', 'reader(').replace('__SLC__(', '')
        if '(out)' in st and re.match(r'(\s*//[^\n]*\n)*\s*let printer', st):
            lines.append('let out = @termcolor.ByteVec::new()')
        lines.append(st)
    text = '\n'.join(lines)
    # re-insert strings
    def rep(m):
        kind, val = strs[int(m.group(1))]
        if kind == 'bytes':
            return mbt_bytes(val)
        return mbt_str(val, indent + 2)
    text = re.sub(r'__STR(\d+)__', rep, text)
    res = ['///|', 'test "%s" {' % name]
    for l in text.split('\n'):
        res.append('  ' + l if l.strip() else l)
    res.append('}')
    return '\n'.join(res) + '\n'

if __name__ == '__main__':
    path, start, header, outp = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    src = open(path).read().split('\n')
    src = '\n'.join(src[start-1:])
    skip = set(sys.argv[5].split(',')) if len(sys.argv) > 5 else set()
    parts = [open(header).read()] if header != '-' else []
    for name, body in find_tests(src):
        if name in skip:
            parts.append('// SKIPPED: %s\n' % name)
            continue
        parts.append(emit_test(name, body))
    open(outp, 'w').write('\n'.join(parts))
