#!/usr/bin/env python3
"""Ship searchable-frame improvement and actionable Web Detection diagnostics."""
from pathlib import Path
from zipfile import ZipFile
import re,os
zip_file=Path('shorts-studio-source.zip')
out=zip_file.with_suffix('.diagnostics.zip')
with ZipFile(zip_file) as zipped:
    entries=[(i,zipped.read(i)) for i in zipped.infolist()]
files={i.filename:raw for i,raw in entries}
ver=files['pubspec.yaml'].decode('utf-8')
m=re.search(r'(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',ver)
if not m:raise RuntimeError('Version missing from app archive')
major,minor,patch,build=map(int,m.groups())
if (major,minor)!=(0,21) or not (1<=patch<=2):
    raise RuntimeError(f'Unexpected source version: {m.group(0)} (expected 0.21.1 or 0.21.2)')
new_version='version: 0.21.3+62'
sources={
    'lib/benchmark_data.dart':'tool/benchmark_data.dart',
    'lib/benchmark_ui.dart':'tool/benchmark_ui.dart',
    'lib/benchmark_oneclick.dart':'tool/benchmark_oneclick.dart',
    'lib/vision_reverse.dart':'tool/vision_reverse.dart',
    'native/android/BenchmarkFrameExtractor.kt':'tool/BenchmarkFrameExtractor.kt',
    'test/benchmark_test.dart':'tool/benchmark_tests.dart',
}
for name in sources:
    if name not in files:raise RuntimeError(f'Source file absent: {name}')
updates={name:Path(file).read_bytes() for name,file in sources.items()}
updates['pubspec.yaml']=ver.replace(m.group(0),new_version,1).encode('utf-8')
if b'discoverReport' not in updates['lib/vision_reverse.dart']:raise RuntimeError('Vision report not integrated')
if b'state.diagnostics' not in updates['lib/benchmark_ui.dart']:raise RuntimeError('Card diagnostics missing')
if b'VisionSearchReport' not in updates['lib/benchmark_oneclick.dart']:raise RuntimeError('One-click diagnostics missing')
with ZipFile(out,'w') as zipped:
    for info,raw in entries:
        zipped.writestr(info,updates.get(info.filename,raw))
os.replace(out,zip_file)
print(f'{m.group(0)} -> {new_version}: video-frame crop and per-card Vision failure metrics.')
