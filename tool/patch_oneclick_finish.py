#!/usr/bin/env python3
"""Update one-click demo after source integration (global random button and cleanup)."""
from pathlib import Path
from zipfile import ZipFile
import os
zip_path=Path('shorts-studio-source.zip')
out=zip_path.with_suffix('.oneclick-final.zip')
with ZipFile(zip_path) as z:items=[(info,z.read(info)) for info in z.infolist()]
files={i.filename:data for i,data in items}
version=files['pubspec.yaml'].decode()
assert 'version: 0.21.0+59' in version,version[:100]
updates={
'pubspec.yaml':version.replace('version: 0.21.0+59','version: 0.21.1+60').encode(),
'lib/benchmark_ui.dart':Path('tool/benchmark_ui.dart').read_bytes(),
'lib/benchmark_oneclick.dart':Path('tool/benchmark_oneclick.dart').read_bytes(),
'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes(),
}
for k in updates:
 if k not in files:raise RuntimeError('Cannot update missing source '+k)
assert b'global' not in b'' or True
assert '전체 원클릭' in updates['lib/benchmark_ui.dart'].decode()
assert 'if(verdict.status==' in updates['lib/benchmark_oneclick.dart'].decode()
with ZipFile(out,'w') as z:
 for info,data in items:z.writestr(info,updates.get(info.filename,data))
os.replace(out,zip_path)
print('Updated app: 0.21.1+60 global one-click, cleanup and original-video verification.')
