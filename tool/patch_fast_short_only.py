#!/usr/bin/env python3
"""Package strict <=60s portrait-only source matching with Korean + Latin OCR."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".shortonly.tmp")
with ZipFile(src) as z:
    entries=[(info,z.read(info)) for info in z.infolist()]
files={info.filename:data for info,data in entries}
old="version: 0.21.18+77"
new="version: 0.21.19+78"
pub=files["pubspec.yaml"].decode("utf8")
if pub.count(old)!=1:
    raise RuntimeError("Wrong base release: "+pub[:130])
mapping={
 "native/android/BenchmarkOcrCrop.kt":"tool/BenchmarkOcrCrop.kt",
 "native/android/BenchmarkFrameExtractor.kt":"tool/BenchmarkFrameExtractor.kt",
 "lib/benchmark_data.dart":"tool/benchmark_data.dart",
 "lib/benchmark_duration.dart":"tool/benchmark_duration.dart",
 "lib/benchmark_stream.dart":"tool/benchmark_stream.dart",
 "lib/benchmark_oneclick.dart":"tool/benchmark_oneclick.dart",
 "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
 "test/benchmark_test.dart":"tool/benchmark_tests.dart",
}
for target in mapping:
    if target not in files:raise RuntimeError("Unexpected ZIP structure: missing "+target)
updates={target:Path(local).read_bytes() for target,local in mapping.items()}
updates["pubspec.yaml"]=pub.replace(old,new).encode("utf8")

# Bootstrap generates or completes the Flutter Android build tree. Add the
# bundled Latin model after the existing Korean model during bootstrap,
# without needing a separate Google Play services model download.
bootstrap=files["tool/bootstrap.py"].decode("utf8")
tag="# BEGIN Latin OCR model v0.21.19"
if tag in bootstrap:raise RuntimeError("Latin bootstrap already patched")
bootstrap+='''

# BEGIN Latin OCR model v0.21.19
from pathlib import Path as _ShortsPath
_gradle_files=[
    _ShortsPath("android/app/build.gradle.kts"),
    _ShortsPath("android/app/build.gradle"),
]
_gradle=next((p for p in _gradle_files if p.is_file()),None)
if _gradle is None:
    raise RuntimeError("Android app Gradle file not found for bundled Latin OCR")
_gradle_text=_gradle.read_text(encoding="utf8")
if "com.google.mlkit:text-recognition:16.0.1" not in _gradle_text:
    if _gradle.name.endswith(".kts"):
        _gradle_text+='\\n\\ndependencies {\\n    implementation("com.google.mlkit:text-recognition:16.0.1")\\n}\\n'
    else:
        _gradle_text+="\\n\\ndependencies {\\n    implementation 'com.google.mlkit:text-recognition:16.0.1'\\n}\\n"
    _gradle.write_text(_gradle_text,encoding="utf8")
# END Latin OCR model v0.21.19
'''
updates["tool/bootstrap.py"]=bootstrap.encode("utf8")
assert b"TextRecognizerOptions.DEFAULT_OPTIONS" in updates["native/android/BenchmarkOcrCrop.kt"]
assert b"newRecognizers()" in updates["native/android/BenchmarkFrameExtractor.kt"]
assert b"maxAutoSeconds=60" in updates["lib/benchmark_data.dart"]
assert b"noDirectEvidenceRounds>=2" in updates["lib/benchmark_ui.dart"]
assert b"videoResolution.width<=s.videoResolution.height" in updates["lib/benchmark_stream.dart"]
with ZipFile(tmp,"w") as z:
    for info,raw in entries:z.writestr(info,updates.get(info.filename,raw))
os.replace(tmp,src)
print("Packaged v0.21.19+78: Korean/Latin OCR, 60s portrait only, smaller streams, 0-evidence short-circuit")
