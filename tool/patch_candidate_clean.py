#!/usr/bin/env python3
"""Final clean one-click source, without any duplicated classes."""
from zipfile import ZipFile
from pathlib import Path
import os
p=Path("shorts-studio-source.zip")
tmp=p.with_suffix(".clean.zip")
with ZipFile(p) as z:rows=[(x,z.read(x)) for x in z.infolist()]
files={x.filename:v for x,v in rows}
pub=files['pubspec.yaml'].decode('utf8')
assert pub.count("version: 0.21.6+65")==1,pub[:100]
dart=Path('tool/benchmark_oneclick.dart').read_text()
if dart.count('class OneClickExplorer {')!=1 or dart.count('class CandidateThumbnail {')!=1:
 raise RuntimeError('Duplicated or missing Dart classes')
if ').hasMatch(videoId))return' in dart:raise RuntimeError('Broken thumbnail snippet remains')
if not dart.strip().endswith('}'):raise RuntimeError('Dart source incomplete')
changes={
 'pubspec.yaml':pub.replace('version: 0.21.6+65','version: 0.21.7+66').encode(),
 'lib/benchmark_oneclick.dart':dart.encode('utf8'),
 'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes()
}
with ZipFile(tmp,'w') as z:
 for info,raw in rows:z.writestr(info,changes.get(info.filename,raw))
os.replace(tmp,p)
print('v0.21.7+66 source reassembled without duplicate class; full CI validation required')
