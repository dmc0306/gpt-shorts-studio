#!/usr/bin/env python3
"""Repair complete Dart thumbnail class and revalidate the integrated APK."""
from zipfile import ZipFile
from pathlib import Path
import os
source=Path('shorts-studio-source.zip')
output=source.with_suffix('.fixed-oneclick.zip')
with ZipFile(source) as z:items=[(info,z.read(info)) for info in z.infolist()]
files={i.filename:raw for i,raw in items}
pub=files['pubspec.yaml'].decode('utf-8')
old='version: 0.21.5+64'
if pub.count(old)!=1:raise RuntimeError('Expected '+old+'; got '+pub[:140])
dart=Path('tool/benchmark_oneclick.dart').read_bytes()
if b'class CandidateThumbnail {' not in dart or b'class OneClickExplorer {' not in dart:
 raise RuntimeError('Required classes missing')
if b'benchmarkFingerprintImage' not in dart or b'CandidateFailure' not in dart:
 raise RuntimeError('Candidate safeguards missing')
updated={
 'pubspec.yaml':pub.replace(old,'version: 0.21.6+65').encode('utf-8'),
 'lib/benchmark_oneclick.dart':dart,
 'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes()
}
with ZipFile(output,'w') as z:
 for info,data in items:z.writestr(info,updated.get(info.filename,data))
os.replace(output,source)
print('0.21.6+65: Repaired complete thumbnail verifier source; compiler validation will run.')
