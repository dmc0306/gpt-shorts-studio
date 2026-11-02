#!/usr/bin/env python3
"""Repair last duplicated source tail; fail fast if any duplicate Dart classes remain."""
from pathlib import Path
from zipfile import ZipFile
import os
path=Path("shorts-studio-source.zip")
out=path.with_suffix(".precision-clean.zip")
with ZipFile(path) as z:items=[(i,z.read(i)) for i in z.infolist()]
files={i.filename:raw for i,raw in items}
pub=files["pubspec.yaml"].decode('utf8')
expected='version: 0.21.13+72'
if pub.count(expected)!=1:raise RuntimeError('Unexpected app version '+pub[:120])
dart=Path("tool/benchmark_data.dart").read_text()
if dart.count('class BenchState {')!=1 or dart.count('class BenchApi {')!=1:
 raise RuntimeError('Duplicated benchmark data classes')
if ').hasMatch(k)){' in dart[dart.index('class BenchApi {'):]:
 raise RuntimeError('Trailing malformed Dart source remains')
if not dart.rstrip().endswith('}'):
 raise RuntimeError('Source file missing closing brace')
updates={
 'lib/benchmark_data.dart':dart.encode('utf8'),
 'lib/benchmark_ui.dart':Path("tool/benchmark_ui.dart").read_bytes(),
 'test/benchmark_test.dart':Path("tool/benchmark_tests.dart").read_bytes(),
 'pubspec.yaml':pub.replace(expected,'version: 0.21.14+73').encode()
}
with ZipFile(out,'w') as z:
 for i,raw in items:z.writestr(i,updates.get(i.filename,raw))
os.replace(out,path)
print('v0.21.14+73 clean, unique BenchState and BenchApi ready for full Flutter/Android verification')
