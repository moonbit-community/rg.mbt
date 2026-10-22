#!/usr/bin/env python3
"""Converts the flag tests in ripgrep's defs.rs into MoonBit tests."""
import re
import sys

sys.path.insert(0, 'scripts')
from rust_tests import convert_strings, extract_tests

src = open(sys.argv[1]).read()
out = []
skipped = []
for name, body in extract_tests(src):
    if not name.startswith('test_'):
        continue
    b = convert_strings(body)
    b = b.replace('None::<&str>', '[]')
    b = b.replace('parse_low_raw(', 'low(')
    b = re.sub(r'parse_low_raw\(\[', 'low([', b)
    b = re.sub(r'\)\s*\.unwrap\(\);', ')', b)
    b = re.sub(r'\)\.unwrap\(\);', ')', b)
    # cfg(unix) blocks test non-UTF-8 OS strings: drop them.
    while '#[cfg(unix)]' in b:
        i = b.index('#[cfg(unix)]')
        j = b.index('{', i)
        depth = 1
        k = j + 1
        while depth:
            if b[k] == '{': depth += 1
            elif b[k] == '}': depth -= 1
            k += 1
        b = b[:i] + b[k:]
    b = re.sub(r'#\[cfg\(target_pointer_width = "64"\)\]', '', b)
    b = re.sub(r'#\[cfg\(not\(target_pointer_width = "64"\)\)\]\s*\{.*?\n    \}', '', b, flags=re.S)
    b = re.sub(r'^\s*use [^;]*;\n', '', b, flags=re.M)
    b = re.sub(r'let mkctx = \|lines\| \{\s*let mut mode = ContextMode::default\(\);\s*mode\.(\w+)\(lines\);\s*mode\s*\};',
               r'let mkctx = (lines : Int) => ContextMode::default().\1(lines)', b)
    b = re.sub(r'mode\.(set_\w+)\((\d+)\);', r'mode = mode.\1(\2);', b)
    b = re.sub(r'let mut (?!mode)', 'let ', b)
    b = re.sub(r'Vec::<[\w:]+>::new\(\)', '[]', b)
    b = re.sub(r'std::ffi::OsString::from\(("(?:[^"\\]|\\.)*")\)', r'\1', b)
    b = re.sub(r'OsString::from\(("(?:[^"\\]|\\.)*")\)', r'\1', b)
    b = re.sub(r'SortMode \{', 'SortMode::{', b)
    b = re.sub(r'TypeChange::(\w+) \{\s*\w+:\s*(.*?)\s*\}', r'TypeChange::\1(\2)', b, flags=re.S)
    b = re.sub(r'BinaryDetection::none\(\)', 'BinaryNone', b)
    b = re.sub(r'assert_eq!\(', 'assert_eq(', b)
    b = re.sub(r'assert!\(([^,;]*?)\);', r'assert_true(\1)', b)
    b = re.sub(r'assert!\((\w+)\.is_err\(\), ("(?:[^"\\]|\\.)*")\);', r'assert_true(\1 is Err(_), msg=\2)', b)
    b = re.sub(r'let result = parse_low_raw\((.*?)\);', r'let result = try_parse(\1)', b, flags=re.S)
    b = re.sub(r'vec!\[', '[', b)
    b = re.sub(r'("(?:[^"\\]|\\.)*")\.to_string\(\)', r'\1', b)
    b = re.sub(r'PathBuf::from\(("(?:[^"\\]|\\.)*")\)', r'\1', b)
    b = re.sub(r'BString::from\(("(?:[^"\\]|\\.)*")\)', r'bs(\1)', b)
    b = re.sub(r'\.into_bytes\(\)', '', b)
    b = re.sub(r'Mode::Search\(SearchMode::(\w+)\)', r'Mode::Search(\1)', b)
    b = re.sub(r'Mode::Generate\(GenerateMode::(\w+)\)', r'Mode::Generate(\1)', b)
    # Put the actual value first so literals get their type from it.
    def swap(m):
        inner = m.group(1)
        depth = 0
        for i, c in enumerate(inner):
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            elif c == ',' and depth == 0:
                a, b2 = inner[:i].strip(), inner[i+1:].strip().rstrip(',')
                if b2.startswith('args.') or b2.startswith('mkctx') :
                    return 'assert_eq(%s, %s)' % (b2, a)
                return m.group(0)
        return m.group(0)
    b = re.sub(r'assert_eq\(((?:[^;])*?)\);', swap, b, flags=re.S)
    b = re.sub(r';\n', '\n', b)
    if 'OsStr' in b or 'cfg(unix)' in b or 'from_bytes' in b:
        skipped.append(name)
    out.append('///|\ntest "flags/%s" {%s}\n' % (name, b))
open(sys.argv[2], 'w').write('\n'.join(out))
print('converted', len(out), 'tests; mentions OsStr:', skipped)
