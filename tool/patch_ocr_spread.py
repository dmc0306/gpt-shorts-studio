#!/usr/bin/env python3
"""Ensure OCR-clean six scene samples span the entire video duration."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path('shorts-studio-source.zip')
temp=src.with_suffix('.distributed.zip')
with ZipFile(src) as z:entries=[(info,z.read(info)) for info in z.infolist()]
files={info.filename:data for info,data in entries}
old='version: 0.21.9+68'
if files['pubspec.yaml'].decode().count(old)!=1:
 raise RuntimeError('Expected 0.21.9+68 with OCR-duration integration')
extractor=Path('tool/BenchmarkFrameExtractor.kt').read_bytes()
assert b'val positions=listOf(0,2,4,6,8,10,1,3,5,7,9,11)' in extractor
updates={
 'native/android/BenchmarkFrameExtractor.kt':extractor,
 'pubspec.yaml':files['pubspec.yaml'].decode().replace(old,'version: 0.21.10+69').encode()
}
with ZipFile(temp,'w') as z:
 for info,raw in entries:z.writestr(info,updates.get(info.filename,raw))
os.replace(temp,src)
print('0.21.10+69 OCR main sample positions cover start, middle and end; extra timestamps fallback on subtitle occlusion.')
