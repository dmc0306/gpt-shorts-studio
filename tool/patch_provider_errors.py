#!/usr/bin/env python3
"""Polish candidate errors after 0.21.4 fallback integration."""
from zipfile import ZipFile
from pathlib import Path
import os
source=Path('shorts-studio-source.zip')
out=source.with_suffix('.errors.zip')
with ZipFile(source) as z:items=[(i,z.read(i)) for i in z.infolist()]
contents={i.filename:b for i,b in items}
version=contents['pubspec.yaml'].decode('utf8')
assert version.count('version: 0.21.4+63')==1,version[:125]
updated={
 'pubspec.yaml':version.replace('version: 0.21.4+63','version: 0.21.5+64').encode(),
 'lib/benchmark_oneclick.dart':Path('tool/benchmark_oneclick.dart').read_bytes(),
 'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes(),
}
for name in updated:
 if name not in contents:raise RuntimeError('Missing '+name)
assert b'CandidateFailure' in updated['lib/benchmark_oneclick.dart']
with ZipFile(out,'w') as z:
 for item,data in items:z.writestr(item,updated.get(item.filename,data))
os.replace(out,source)
print('Updated 0.21.5+64 provider failure classification and safe candidate UI messages')
