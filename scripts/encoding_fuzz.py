#!/usr/bin/env python3
"""Differential fuzzing of transcoding against a reference ripgrep binary.

Usage: scripts/encoding_fuzz.py <reference rg> <port rg> [seed] [cases per encoding]

Feeds random byte strings built from tricky pieces (BOMs and their
fragments, truncated multi-byte sequences, surrogates) through
`rg -E <enc> -a --passthru -N ''` with both binaries and reports any
difference in output or exit status.
"""
import random, subprocess, sys
R, N = sys.argv[1], sys.argv[2]
random.seed(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
encs = [None, 'utf-8', 'utf-16le', 'utf-16be', 'big5', 'shift_jis', 'euc-kr', 'euc-jp', 'gbk', 'gb18030', 'iso-2022-jp', 'windows-1252', 'latin1', 'koi8-r', 'x-user-defined']
pieces = [b'\xef\xbb\xbf', b'\xff\xfe', b'\xfe\xff', b'\xef\xbb', b'\xff', b'\xfe', b'\xd8\x00', b'\x00\xd8', b'\xdc\x00', b'\x00\xdc',
          b'\xe2\x82', b'\xe2\x82\xac', b'\xf0\x9f\x98', b'\x81', b'\xe8', b'\x84Y', b'\xa4\x40', b'\x8f\xa1', b'\x1b$B', b'\x1b(B', b'\x1b',
          b'a', b'b', b'\n', b'\r\n', b'\x00', b'\x80', b'\xc3\xa9', b'\x30', b'\xa1\xa1']
diffs = 0; total = 0
for enc in encs:
    for _ in range(int(sys.argv[4]) if len(sys.argv) > 4 else 150):
        data = b''.join(random.choice(pieces) for _ in range(random.randint(0, 6)))
        args = ['--no-config', '-a', '--passthru', '-N', '']
        if enc: args = ['-E', enc] + args
        outs = [subprocess.run([b] + args, input=data, capture_output=True) for b in (R, N)]
        total += 1
        if (outs[0].returncode, outs[0].stdout, outs[0].stderr) != (outs[1].returncode, outs[1].stdout, outs[1].stderr):
            diffs += 1
            if diffs <= 12:
                print('DIFF', enc, data, '\n   rg  :', outs[0].returncode, outs[0].stdout, outs[0].stderr, '\n   ours:', outs[1].returncode, outs[1].stdout, outs[1].stderr)
print(f'{diffs} diffs / {total}')
