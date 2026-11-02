#!/usr/bin/env python3
"""Repair release v0.21.12's original-source state parser and UI variable collision."""
from zipfile import ZipFile
from pathlib import Path
import os
archive=Path('shorts-studio-source.zip')
out=archive.with_suffix('.precision-fixed.zip')
with ZipFile(archive) as z:rows=[(x,z.read(x)) for x in z.infolist()]
current={x.filename:raw for x,raw in rows}
version=current['pubspec.yaml'].decode('utf8')
old='version: 0.21.12+71'
if version.count(old)!=1:raise RuntimeError('Expected '+old+', got '+version[:160])
src1=Path('tool/benchmark_data.dart').read_text()
src2=Path('tool/benchmark_ui.dart').read_text()
assert 'factory BenchState.fromJson' in src1 and "if(raw['rejected'] is Map)" in src1
assert "final manualSources=" in src2 and 'if(manual)' in src2
assert "RegExp(r'^UC[\\w-]{22}$')" in src1
fixed={
 'lib/benchmark_data.dart':src1.encode(),
 'lib/benchmark_ui.dart':src2.encode(),
 'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes(),
 'pubspec.yaml':version.replace(old,'version: 0.21.13+72').encode()
}
with ZipFile(out,'w') as z:
 for x,raw in rows:z.writestr(x,fixed.get(x.filename,raw))
os.replace(out,archive)
print('v0.21.13+72 fixed state factory and shadowed search parameter.')
