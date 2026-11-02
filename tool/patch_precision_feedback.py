#!/usr/bin/env python3
"""Prioritize actual per-page image matches, suppress weak leads and remember source judgments."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path('shorts-studio-source.zip');tmp=src.with_suffix('.precision.zip')
with ZipFile(src) as z:rows=[(i,z.read(i)) for i in z.infolist()]
files={i.filename:raw for i,raw in rows}
pub=files['pubspec.yaml'].decode('utf8')
previous='version: 0.21.11+70'
if pub.count(previous)!=1:
    raise RuntimeError('Expected '+previous+'; got '+pub[:120])
changes={
  'pubspec.yaml':pub.replace(previous,'version: 0.21.12+71').encode(),
  'lib/benchmark_data.dart':Path('tool/benchmark_data.dart').read_bytes(),
  'lib/benchmark_ui.dart':Path('tool/benchmark_ui.dart').read_bytes(),
  'lib/benchmark_oneclick.dart':Path('tool/benchmark_oneclick.dart').read_bytes(),
  'lib/vision_reverse.dart':Path('tool/vision_reverse.dart').read_bytes(),
  'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes()
}
for name in changes:
    if name not in files:raise RuntimeError('Missing '+name)
assert b'ignoredUrls' in changes['lib/benchmark_oneclick.dart']
assert b'state.rejected' in changes['lib/benchmark_ui.dart']
assert '연관 페이지만 확인' in changes['lib/vision_reverse.dart'].decode('utf8')
assert '원본 확인' in changes['lib/benchmark_ui.dart'].decode('utf8')
with ZipFile(tmp,'w') as z:
  for i,raw in rows:z.writestr(i,changes.get(i.filename,raw))
os.replace(tmp,src)
print('v0.21.12+71 strict page-local image signals, weak lead suppression, saved negative/positive feedback')
