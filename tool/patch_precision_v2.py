#!/usr/bin/env python3
"""Package chronological, crop-aligned candidate matching as source v0.21.15+74."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path('shorts-studio-source.zip')
tmp=src.with_suffix('.precision-v2.zip')
with ZipFile(src) as z:
    entries=[(info,z.read(info)) for info in z.infolist()]
files={item.filename:data for item,data in entries}
pub=files['pubspec.yaml'].decode('utf-8')
old='version: 0.21.14+73'
if pub.count(old)!=1:
    raise RuntimeError('Expected '+old+'; got '+pub[:100])
updates={
    'pubspec.yaml':pub.replace(old,'version: 0.21.15+74').encode('utf-8'),
    'lib/benchmark_oneclick.dart':Path('tool/benchmark_oneclick.dart').read_bytes(),
    'native/android/BenchmarkFrameExtractor.kt':Path('tool/BenchmarkFrameExtractor.kt').read_bytes(),
    'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes(),
}
for name in updates:
    if name not in files:raise RuntimeError('App source missing '+name)
if b'cropIndex' not in updates['lib/benchmark_oneclick.dart']:
    raise RuntimeError('Matcher lacks crop index')
if b'"cropIndex" to cropIndex' not in updates['native/android/BenchmarkFrameExtractor.kt']:
    raise RuntimeError('Candidate extractor lacks crop index')
if b'benchmarkGroundTruth' not in updates['test/benchmark_test.dart']:
    raise RuntimeError('Ground truth regression lost')
with ZipFile(tmp,'w') as z:
    for info,raw in entries:
        z.writestr(info,updates.get(info.filename,raw))
os.replace(tmp,src)
print('0.21.15+74 packaged; chronological scene matching, crop proof and central OCR checks')
