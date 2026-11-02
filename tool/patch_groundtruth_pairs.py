#!/usr/bin/env python3
"""Register user-provided benchmark ground-truth and support secure TikTok short links."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path('shorts-studio-source.zip')
out=src.with_suffix('.groundtruth.zip')
with ZipFile(src) as z:items=[(info,z.read(info)) for info in z.infolist()]
files={info.filename:data for info,data in items}
old="version: 0.21.10+69"
ver=files['pubspec.yaml'].decode('utf8')
if ver.count(old)!=1:raise RuntimeError('Unexpected app version: '+ver[:120])
changed={
 'pubspec.yaml':ver.replace(old,'version: 0.21.11+70').encode('utf8'),
 'lib/benchmark_data.dart':Path('tool/benchmark_data.dart').read_bytes(),
 'lib/benchmark_ui.dart':Path('tool/benchmark_ui.dart').read_bytes(),
 'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes()
}
if b'NPom9sHH2J0' not in changed['lib/benchmark_data.dart'] or b'ZSp11jbJd' not in changed['lib/benchmark_data.dart']:raise RuntimeError('Known sample pair absent')
if b'state.confirmed' not in changed['lib/benchmark_ui.dart']:raise RuntimeError('User original not displayed')
if b"h=='vt.tiktok.com'" not in changed['lib/benchmark_data.dart']:raise RuntimeError('TikTok share link handling absent')
with ZipFile(out,'w') as z:
 for info,raw in items:z.writestr(info,changed.get(info.filename,raw))
os.replace(out,src)
print('0.21.11+70 benchmark ground truth stored independently; short TikTok links and manual sources survive repeat search.')
