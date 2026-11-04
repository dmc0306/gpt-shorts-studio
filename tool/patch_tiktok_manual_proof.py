#!/usr/bin/env python3
"""Package TikTok extractor-failure recovery using local-file scene proof."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".tiktokproof.tmp")
with ZipFile(src) as archive:
    entries=[(info,archive.read(info)) for info in archive.infolist()]
existing={info.filename:raw for info,raw in entries}
old="version: 0.21.20+79"
new="version: 0.21.21+80"
pub=existing["pubspec.yaml"].decode("utf8")
if pub.count(old)!=1:
    raise RuntimeError("Unexpected base version "+pub[:140])
mapping={
    "lib/benchmark_data.dart":"tool/benchmark_data.dart",
    "lib/benchmark_oneclick.dart":"tool/benchmark_oneclick.dart",
    "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
    "test/benchmark_test.dart":"tool/benchmark_tests.dart",
}
for name in mapping:
    if name not in existing:
        raise RuntimeError("Missing app module "+name)
updates={dest:Path(srcpath).read_bytes() for dest,srcpath in mapping.items()}
updates["pubspec.yaml"]=pub.replace(old,new).encode("utf8")
assert b"LocalVideoProof" in updates["lib/benchmark_oneclick.dart"]
assert b"Future<void> verifyCandidateFromFile" in updates["lib/benchmark_ui.dart"]
assert b"Future<void> confirmFootageMatch" in updates["lib/benchmark_ui.dart"]
assert b"matchedByUser" in updates["lib/benchmark_data.dart"]
assert b"User-recognized TikTok" in updates["test/benchmark_test.dart"]
with ZipFile(tmp,"w") as archive:
    for info,body in entries:
        archive.writestr(info,updates.get(info.filename,body))
os.replace(tmp,src)
print("Packaged v0.21.21+80 TikTok 10204 fallback, local 3-scene check and separately labeled human match")
