#!/usr/bin/env python3
"""Package Material 3 benchmark UX and search-history backup into Shorts Studio."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".ux-rebuild.tmp")
with ZipFile(src) as archive:
    entries=[(info,archive.read(info)) for info in archive.infolist()]
existing={info.filename:data for info,data in entries}
pub=existing["pubspec.yaml"].decode("utf8")
old="version: 0.21.19+78"
new="version: 0.21.20+79"
if pub.count(old)!=1:raise RuntimeError("Unexpected source app version: "+pub[:140])
mapping={
    "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
    "test/benchmark_test.dart":"tool/benchmark_tests.dart",
}
for target in mapping:
    if target not in existing:raise RuntimeError("Missing app source file: "+target)
updates={target:Path(local).read_bytes() for target,local in mapping.items()}
updates["pubspec.yaml"]=pub.replace(old,new).encode("utf8")
ui=updates["lib/benchmark_ui.dart"]
tests=updates["test/benchmark_test.dart"]
for required in [
    b"Future<void> exportBackup()",
    b"Future<void> restoreBackup()",
    b"Future<void> removeChannel(",
    b"Widget candidateTile(",
    b"Widget candidateCard(",
    b"ExpansionTile(",
    "자막 없는 원본 찾기".encode("utf8"),
    "API 키 및 검색 기록".encode("utf8")
]:
    if required not in ui:raise RuntimeError("Missing expected UX feature")
assert b"Search-history backup roundtrip" in tests
with ZipFile(tmp,"w") as archive:
    for info,data in entries:
        archive.writestr(info,updates.get(info.filename,data))
os.replace(tmp,src)
print("Packaged v0.21.20+79 benchmark UX, safe channel removal, history backup")
