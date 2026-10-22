#!/usr/bin/env python3
"""Generates MoonBit tests whose expected output comes from the real `rg`.

Usage (from this directory):
  python3 gen_rg_compat.py sh > rg_compat/run.sh
  (cd rg_compat && sh run.sh)          # needs `rg` on PATH; writes rg_compat/out/
  python3 gen_rg_compat.py normalize   # rewrites rg_compat/out/ (see below)
  python3 gen_rg_compat.py mbt         # writes ../rg_compat_test.mbt
  moon fmt

The checked-in outputs in rg_compat/out/ were produced by ripgrep 15.1.0 and
are stored normalized: the absolute path of the data directory is replaced by
`/work` and the machine's hostname by `myhost`, so that they don't depend on
(or reveal) where they were generated.
"""
import re, sys, os, shlex, socket

HOST = socket.gethostname()
DATA = os.path.abspath(os.path.join(os.path.dirname(__file__), 'rg_compat'))

COLORS = '.color_specs(@printer.ColorSpecs::default_with_color())'

def std(name, args, pattern, file='sherlock', popts='', sopts='', mopts='',
        ansi=True, path=True, colors=COLORS, multiline=False, binary=True,
        canon=False, env_host=False, nopath_sink=False, line_number=True):
    return dict(kind='std', name=name, args=args, pattern=pattern, file=file,
                popts=popts, sopts=sopts, mopts=mopts, ansi=ansi, path=path,
                colors=colors, multiline=multiline, binary=binary, canon=canon,
                env_host=env_host, line_number=line_number)

SCENARIOS = [
    std('color_basic', ['-n', '-H', '--no-heading'], 'Sherlock'),
    std('color_no_line_number', ['-N', '-H', '--no-heading'], 'Sherlock', line_number=False),
    std('color_heading', ['-n', '--heading', '-H'], 'Sherlock', popts='.heading(true)'),
    std('color_context', ['-n', '-H', '--no-heading', '-C1'], 'Watson',
        sopts='.before_context(1).after_context(1)'),
    std('color_context_heading', ['-n', '-H', '--heading', '-C1'], 'Watson',
        sopts='.before_context(1).after_context(1)', popts='.heading(true)'),
    std('color_column_byte_offset', ['-n', '-H', '--no-heading', '--column', '-b'], 'Watson',
        popts='.column(true).byte_offset(true)'),
    std('color_only_matching', ['-n', '-H', '--no-heading', '-o'], r'Sherl\w+|Hol\w+',
        popts='.only_matching(true)'),
    std('color_vimgrep', ['--vimgrep'], 'Doctor|Holmes',
        popts='.column(true).per_match(true)'),
    std('color_replace', ['-n', '-H', '--no-heading', '-r', '[$1]'], 'Sher(lock)',
        popts='.replacement(Some(b"[$1]"))'),
    std('color_replace_only_matching', ['-n', '-o', '-r', '<$0>'], 'o[a-z]',
        popts='.replacement(Some(b"<$0>")).only_matching(true)', path=False),
    std('color_multiline', ['-n', '-H', '--no-heading', '-U'], r'Sherlock\nHolmeses',
        multiline=True),
    std('color_multiline_context', ['-n', '-H', '--no-heading', '-U', '-C1'], r'luck\. Sherlock Holmes\ncan',
        multiline=True, sopts='.before_context(1).after_context(1)'),
    std('color_multiline_only_matching', ['-n', '-H', '--no-heading', '-U', '-o'], r'Sherlock\nHolmeses',
        multiline=True, popts='.only_matching(true)'),
    std('color_multiline_vimgrep', ['--vimgrep', '-U'], r'Sherlock\nHolmeses|Watson',
        multiline=True, popts='.column(true).per_match(true)'),
    std('color_max_columns', ['-n', '-H', '--no-heading', '-M', '30'], 'Sherlock',
        popts='.max_columns(Some(30))'),
    std('color_max_columns_preview', ['-n', '-H', '--no-heading', '-M', '30', '--max-columns-preview'],
        'Sherlock', popts='.max_columns(Some(30)).max_columns_preview(true)'),
    std('graphemes_max_columns_preview', ['-n', '-M', '9', '--max-columns-preview'],
        'Sherlock', file='graph', popts='.max_columns(Some(9)).max_columns_preview(true)', path=False),
    std('custom_colors', ['-n', '-H', '--no-heading',
                          '--colors', 'match:bg:yellow', '--colors', 'match:fg:0x10',
                          '--colors', 'line:style:underline', '--colors', 'path:fg:255,0,128',
                          '--colors', 'highlight:bg:blue', '--colors', 'column:fg:cyan',
                          '--colors', 'column:style:intense', '--column'],
        'Sherlock',
        colors='.color_specs(@printer.ColorSpecs::new([..@printer.default_color_specs(), @printer.UserColorSpec::parse("match:bg:yellow"), @printer.UserColorSpec::parse("match:fg:0x10"), @printer.UserColorSpec::parse("line:style:underline"), @printer.UserColorSpec::parse("path:fg:255,0,128"), @printer.UserColorSpec::parse("highlight:bg:blue"), @printer.UserColorSpec::parse("column:fg:cyan"), @printer.UserColorSpec::parse("column:style:intense")]))',
        popts='.column(true)'),
    std('colors_none', ['-n', '-H', '--no-heading', '--colors', 'match:none', '--colors', 'path:none', '-C1'],
        'Watson', sopts='.before_context(1).after_context(1)',
        colors='.color_specs(@printer.ColorSpecs::new([..@printer.default_color_specs(), @printer.UserColorSpec::parse("match:none"), @printer.UserColorSpec::parse("path:none")]))'),
    std('trim', ['-n', '--trim'], 'Sherlock|Watson', file='indented', popts='.trim_ascii(true)', path=False),
    std('trim_only_matching', ['-n', '--trim', '-o'], r'\s+\S+', file='indented',
        popts='.trim_ascii(true).only_matching(true)', path=False),
    std('invert', ['-n', '-H', '--no-heading', '-v'], 'Sherlock|Watson', sopts='.invert_match(true)'),
    std('invert_context', ['-n', '-H', '--no-heading', '-v', '-C1'], 'Holmeses|cigar',
        sopts='.invert_match(true).before_context(1).after_context(1)'),
    std('separators', ['-n', '-H', '--no-heading', '-C1', '--field-match-separator', '::',
                       '--field-context-separator', '~~', '--context-separator', '##'], 'Doctor',
        sopts='.before_context(1).after_context(1)',
        popts='.separator_field_match(b"::").separator_field_context(b"~~").separator_context(Some(b"##"))'),
    std('null_terminator', ['-n', '-H', '--no-heading', '-0'], 'Sherlock',
        popts='.path_terminator(Some(b\'\\x00\'))'),
    std('null_terminator_heading', ['-n', '-H', '--heading', '-0'], 'Sherlock',
        popts='.path_terminator(Some(b\'\\x00\')).heading(true)'),
    std('path_separator', ['-n', '-H', '--no-heading', '--path-separator', '@'], 'Sherlock',
        file='./sherlock', popts='.separator_path(Some(b\'@\'))'),
    std('binary_convert', ['-n', '-H', '--no-heading'], 'Sherlock', file='bin2'),
    std('binary_convert_first', ['-n', '-H', '--no-heading'], 'Sherlock', file='bin1'),
    std('latin1_no_color', ['-n', '-H', '--no-heading'], 'Sherlock', file='latin1', ansi=False),
    std('hyperlink_vscode', ['-n', '-H', '--no-heading', '--hyperlink-format', 'vscode', '--column'],
        'Sherlock', canon=True,
        popts='.column(true).hyperlink(@printer.HyperlinkFormat::parse("vscode").into_config(env))'),
    std('hyperlink_heading_file', ['-n', '-H', '--heading', '--hyperlink-format', 'file'],
        'Sherlock', canon=True, env_host=True,
        popts='.heading(true).hyperlink(@printer.HyperlinkFormat::parse("file").into_config(env))'),
    std('hyperlink_heading_kitty', ['-n', '-H', '--heading', '--hyperlink-format', 'kitty'],
        'Sherlock', canon=True, env_host=True,
        popts='.heading(true).hyperlink(@printer.HyperlinkFormat::parse("kitty").into_config(env))'),
    std('hyperlink_context', ['-n', '-H', '--no-heading', '-C1', '--hyperlink-format', 'grep+'],
        'Watson', canon=True, sopts='.before_context(1).after_context(1)',
        popts='.hyperlink(@printer.HyperlinkFormat::parse("grep+").into_config(env))'),
    std('passthru', ['-n', '--passthru'], 'Watson', sopts='.passthru(true)', path=False),
    std('max_count_after', ['-n', '-m1', '-A2'], 'Doctor', sopts='.max_matches(Some(1)).after_context(2)', path=False),
    std('crlf', ['-n', '--crlf'], 'Sherlock$|^can', file='crlf', mopts='.crlf(true)',
        sopts='.line_terminator(@matcher.LineTerminator::crlf())', path=False),
    std('crlf_only_matching', ['-n', '--crlf', '-o'], r'\w+$', file='crlf', mopts='.crlf(true)',
        sopts='.line_terminator(@matcher.LineTerminator::crlf())', path=False, popts='.only_matching(true)'),
    std('byte_offset_only_matching', ['-n', '-b', '-o'], 'o[a-z]', popts='.byte_offset(true).only_matching(true)', path=False),
    std('column_context', ['-n', '--column', '-C1'], 'Watson', popts='.column(true)',
        sopts='.before_context(1).after_context(1)', path=False),
    std('max_columns_context', ['-n', '-M', '20', '-C1'], 'Watson', popts='.max_columns(Some(20))',
        sopts='.before_context(1).after_context(1)', path=False),
    std('max_columns_only_matching_preview', ['-n', '-o', '-M', '5', '--max-columns-preview'], 'Sherlock',
        popts='.max_columns(Some(5)).max_columns_preview(true).only_matching(true)', path=False),
    std('max_columns_preview_context', ['-n', '-M', '10', '--max-columns-preview', '-C1'], 'Watson',
        popts='.max_columns(Some(10)).max_columns_preview(true)',
        sopts='.before_context(1).after_context(1)', path=False),
    std('multiline_max_columns_preview', ['-n', '-U', '-M', '10', '--max-columns-preview'], r'Sherlock\nHolmeses',
        multiline=True, popts='.max_columns(Some(10)).max_columns_preview(true)', path=False),
    std('multiline_no_color', ['-n', '-U'], r'Sherlock\nHolmeses', multiline=True, ansi=False, path=False),
    std('multiline_heading', ['-n', '-U', '--heading', '-H', '-b'], r'Sherlock\nHolmeses', multiline=True,
        popts='.heading(true).byte_offset(true)'),
    dict(kind='summary', name='summary_count', args=['-c', '-H'], pattern='Sherlock',
         sum_kind='Count'),
    dict(kind='summary', name='summary_count_matches', args=['--count-matches', '-H'], pattern='o',
         sum_kind='CountMatches'),
    dict(kind='summary', name='summary_files_with_matches', args=['-l'], pattern='Sherlock',
         sum_kind='PathWithMatch'),
    dict(kind='summary', name='summary_files_with_matches_null', args=['-l', '-0'], pattern='Sherlock',
         sum_kind='PathWithMatch', popts='.path_terminator(Some(b\'\\x00\'))'),
    dict(kind='summary', name='summary_files_without_match', args=['--files-without-match'],
         pattern='ZZZ', sum_kind='PathWithoutMatch'),
    dict(kind='summary', name='summary_count_hyperlink', args=['-c', '-H', '--hyperlink-format', 'vscode'],
         pattern='Sherlock', sum_kind='Count', canon=True,
         popts='.hyperlink(@printer.HyperlinkFormat::parse("vscode").into_config(env))'),
    dict(kind='path', name='path_printer_basic', args=['--files'], file='sherlock'),
    dict(kind='path', name='path_printer_null_sep', args=['--files', '-0', '--path-separator', '@'],
         file='./sherlock', canon=True,
         popts='.terminator(b\'\\x00\').separator(Some(b\'@\')).hyperlink(@printer.HyperlinkFormat::parse("vscode").into_config(env))',
         extra=['--hyperlink-format', 'vscode']),
    dict(kind='path', name='path_printer_hyperlink', args=['--files', '--hyperlink-format', 'vscode'],
         file='./sherlock', canon=True,
         popts='.hyperlink(@printer.HyperlinkFormat::parse("vscode").into_config(env))'),
    dict(kind='json', name='json_basic', args=['--json'], pattern='Watson'),
    dict(kind='json', name='json_pretty_context', args=['--json', '-C1'], pattern='Watson',
         sopts='.before_context(1).after_context(1)', popts='.pretty(true)', pretty=True),
    dict(kind='json', name='json_pretty_non_utf8', args=['--json'], pattern='Sherlock', file='latin1',
         popts='.pretty(true)', pretty=True),
    dict(kind='json', name='json_context', args=['--json', '-C1'], pattern='Watson',
         sopts='.before_context(1).after_context(1)'),
    dict(kind='json', name='json_replace', args=['--json', '-r', '<$0>'], pattern='Sher(lock)',
         popts='.replacement(Some(b"<$0>"))'),
    dict(kind='json', name='json_invert', args=['--json', '-v', '-n'], pattern='o',
         sopts='.invert_match(true)'),
    dict(kind='json', name='json_non_utf8', args=['--json'], pattern='Sherlock', file='latin1'),
    dict(kind='json', name='json_binary', args=['--json'], pattern='Sherlock', file='bin2'),
    dict(kind='json', name='json_multiline', args=['--json', '-U'], pattern=r'Sherlock\nHolmeses',
         multiline=True),
]

def out_path(s):
    return os.path.join('out', s['name'] + '.out')

def rg_cmd(s):
    args = ['rg'] + s['args']
    if s['kind'] == 'std':
        args.append('--color=always' if s['ansi'] else '--color=never')
    elif s['kind'] == 'summary':
        args.append('--color=always')
    elif s['kind'] == 'path':
        args += s.get('extra', []) + ['--color=always', s['file']]
        return ' '.join(shlex.quote(a) for a in args) + ' > ' + shlex.quote(out_path(s))
    args += ['-e', s['pattern'], s.get('file', 'sherlock')]
    return ' '.join(shlex.quote(a) for a in args) + ' > ' + shlex.quote(out_path(s))

def mbt_string(b):
    res = []
    i = 0
    s = b.decode('utf-8', errors='surrogateescape')
    for c in s:
        o = ord(c)
        if 0xdc80 <= o <= 0xdcff:
            raise Exception('non-utf8 output; use bytes')
        if c == '\n': res.append('\\n')
        elif c == '\r': res.append('\\r')
        elif c == '\t': res.append('\\t')
        elif c == '\\': res.append('\\\\')
        elif c == '"': res.append('\\"')
        elif o < 0x20 or o == 0x7f: res.append('\\u{%x}' % o)
        else: res.append(c)
    return '"' + ''.join(res) + '"'

def mbt_bytes(b):
    res = []
    for o in b:
        c = chr(o)
        if c == '\n': res.append('\\n')
        elif c == '\r': res.append('\\r')
        elif c == '\t': res.append('\\t')
        elif c == '\\': res.append('\\\\')
        elif c == '"': res.append('\\"')
        elif o < 0x20 or o >= 0x7f: res.append('\\x%02x' % o)
        else: res.append(c)
    return 'b"' + ''.join(res) + '"'

def expected_literal(b):
    try:
        b.decode('utf-8')
        return 'str', mbt_string(b)
    except UnicodeDecodeError:
        return 'bytes', mbt_bytes(b)

def normalize(s, b):
    # Replace the real absolute data dir with a fixed fake one.
    b = b.replace(DATA.encode(), b'/work')
    b = b.replace(HOST.encode(), b'myhost')
    if s['kind'] == 'json':
        # Drop the summary message (printed by ripgrep's main, not the printer).
        lines = [l for l in b.split(b'\n') if l and not l.startswith(b'{"data":{"elapsed_total"')]
        lines = [re.sub(rb'"elapsed":\{"secs":\d+,"nanos":\d+,"human":"[0-9.]+s"\}',
                        b'"elapsed":{"secs":0,"nanos":0,"human":"0.000000s"}', l) for l in lines]
        if s.get('pretty'):
            import json
            objs = [json.loads(l) for l in lines]
            printed = 0
            out = []
            for o in objs:
                if o['type'] == 'end':
                    # bytes_printed counts the (pretty) messages before 'end'.
                    o['data']['stats']['bytes_printed'] = printed
                enc = json.dumps(o, indent=2, ensure_ascii=False).encode()
                printed += len(enc) + 1
                out.append(enc)
            lines = out
        b = b''.join(l + b'\n' for l in lines)
    return b

def matcher_code(s):
    pat = mbt_string(s['pattern'].encode())
    ml = s.get('multiline', False)
    code = '@grep_regex.RegexMatcherBuilder::new().multi_line(true)'
    if not ml:
        code += '.line_terminator(Some(b\'\\n\'))'
    code += '.ban_byte(Some(b\'\\x00\'))'
    code += s.get('mopts', '')
    return code + '.build(%s)' % pat

def searcher_code(s):
    code = '@searcher.SearcherBuilder::new()'
    a = s['args']
    if s['kind'] == 'summary':
        ln = False
    elif s['kind'] == 'json':
        ln = '-N' not in a
    else:
        ln = ('-n' in a or '--column' in a or '--vimgrep' in a) and '-N' not in a
    code += '.line_number(%s)' % ('true' if ln else 'false')
    if s.get('multiline', False):
        code += '.multi_line(true)'
    code += '.binary_detection(@searcher.BinaryDetection::BinaryConvert(b\'\\x00\'))'
    code += s.get('sopts', '')
    return code + '.build()'

def env_code(s):
    host = 'Some("myhost")' if s.get('env_host') else 'None'
    return ('let env = @printer.HyperlinkEnvironment::new().host(%s)'
            '.canonicalize(Some(fake_canonicalize))') % host

def emit(s):
    name = s['name']
    data = open(os.path.join(DATA, out_path(s)), 'rb').read()
    data = normalize(s, data)
    kind, lit = expected_literal(data)
    file = s.get('file', 'sherlock')
    fname = os.path.basename(file)
    L = ['///|', 'test "rg_compat_%s" {' % name]
    if s['kind'] == 'path':
        L.append('  // rg %s' % ' '.join(shlex.quote(a) for a in s['args'] + s.get('extra', []) + [file]))
        if s.get('canon'):
            L.append('  ' + env_code(s))
        L.append('  let out = @termcolor.ByteVec::new()')
        L.append('  let printer = @printer.PathPrinterBuilder::new().color_specs(@printer.ColorSpecs::default_with_color())%s.build(@termcolor.Ansi::new(out))' % s.get('popts', ''))
        L.append('  printer.write(%s)' % mbt_string(file.encode()))
        L.append('  assert_eq(contents(out), %s)' % lit)
        L.append('}')
        return '\n'.join(L) + '\n'
    L.append('  // rg %s' % ' '.join(shlex.quote(a) for a in s['args'] + ['-e', s['pattern'], file]))
    L.append('  let haystack = %s' % mbt_bytes(open(os.path.join(DATA, fname), 'rb').read()))
    L.append('  let matcher = %s' % matcher_code(s))
    if s.get('canon') or 'hyperlink' in s.get('popts', ''):
        L.append('  ' + env_code(s))
    L.append('  let out = @termcolor.ByteVec::new()')
    if s['kind'] == 'std':
        wtr = '@termcolor.Ansi::new(out)' if s['ansi'] else '@termcolor.NoColor::new(out)'
        colors = s['colors'] if s['ansi'] else ''
        path_flag = 'true' if ('-H' in s['args'] or '--vimgrep' in s['args']) else 'false'
        L.append('  let printer = @printer.StandardBuilder::new()%s.path(%s).per_match_one_line(true)%s.build(%s)'
                 % (colors, path_flag, s['popts'], wtr))
        sink = 'printer.sink_with_path(matcher, %s)' % mbt_string(file.encode())
    elif s['kind'] == 'summary':
        path_flag = 'true' if ('-H' in s['args']) else 'false'
        L.append('  let printer = @printer.SummaryBuilder::new().color_specs(@printer.ColorSpecs::default_with_color()).kind(@printer.SummaryKind::%s).path(%s)%s.build(@termcolor.Ansi::new(out))'
                 % (s['sum_kind'], path_flag, s.get('popts', '')))
        sink = 'printer.sink_with_path(matcher, %s)' % mbt_string(file.encode())
    else:
        L.append('  let printer = @printer.JSONBuilder::new()%s.build(out)' % s.get('popts', ''))
        sink = 'printer.sink_with_path(matcher, %s)' % mbt_string(file.encode())
    L.append('  %s.search_reader(matcher, reader(haystack), %s)' % (searcher_code(s), sink))
    if kind == 'str':
        L.append('  assert_eq(contents(out), %s)' % lit)
    else:
        L.append('  assert_eq(out.to_bytes(), %s)' % lit)
    L.append('}')
    return '\n'.join(L) + '\n'

if __name__ == '__main__':
    if sys.argv[1] == 'sh':
        print('mkdir -p out')
        for s in SCENARIOS:
            print(rg_cmd(s))
    elif sys.argv[1] == 'normalize':
        out = os.path.join(DATA, 'out')
        for name in sorted(os.listdir(out)):
            path = os.path.join(out, name)
            b = open(path, 'rb').read()
            n = b.replace(DATA.encode(), b'/work').replace(HOST.encode(), b'myhost')
            if n != b:
                open(path, 'wb').write(n)
    else:
        parts = [emit(s) for s in SCENARIOS]
        hdr = ('///|\n/// Canonicalizes paths of files that exist in the test data directory\n'
               '/// (mounted at `/work`), failing for anything else.\n'
               'fn fake_canonicalize(p : String) -> String? {\n'
               '  match p {\n'
               '    "sherlock" | "./sherlock" => Some("/work/sherlock")\n'
               '    _ => None\n'
               '  }\n'
               '}\n\n') + ('// Tests generated by running the real `rg` (ripgrep 15.1.0) and comparing\n'
               '// the printer output byte for byte. Absolute paths are normalized to\n'
               '// `/work`, the hostname to `myhost` and JSON timings to zero.\n\n')
        open(os.path.join(os.path.dirname(__file__), '..', 'rg_compat_test.mbt'), 'w').write(hdr + '\n'.join(parts))
