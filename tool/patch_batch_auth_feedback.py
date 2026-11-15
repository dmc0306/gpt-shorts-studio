#!/usr/bin/env python3
"""Update shipped Flutter ZIP with honest upload status and Chrome preflight.

Runs in packaging CI only; not involved in background Shorts scheduling.
Stops on unexpected source versions or UI anchors to avoid silent mismatches.
"""
from __future__ import annotations

import os
from pathlib import Path
from zipfile import ZipFile

src = Path("shorts-studio-source.zip")
tmp = src.with_suffix(".batch-auth.tmp")
replacement = {
    "lib/youtube_batch_publish_screen.dart":
        Path("tool/youtube_batch_publish_screen.dart").read_bytes(),
    "lib/youtube_batch_outcome.dart":
        Path("tool/youtube_batch_outcome.dart").read_bytes(),
    "test/youtube_batch_outcome_test.dart":
        Path("tool/youtube_batch_outcome_test.dart").read_bytes(),
}
if not src.is_file():
    raise RuntimeError("Flutter source ZIP is missing")
with ZipFile(src) as archive:
    entries = [(info, archive.read(info)) for info in archive.infolist()]
files = {info.filename: blob for info, blob in entries}
old_version = b"version: 0.21.26+85"
new_version = b"version: 0.21.27+86"
if files["pubspec.yaml"].count(old_version) != 1:
    raise RuntimeError("Unexpected source version. Refuse unsafe ZIP overwrite.")
original = files["lib/youtube_batch_publish_screen.dart"].decode("utf-8")
anchors = (
    "선택한 영상의 전송 시도를 마쳤어요",
    "게시 예정 시간",
    "final id=await youtube.uploadClip(item);",
)
for anchor in anchors:
    if original.count(anchor) != 1:
        raise RuntimeError(f"Outdated batch UI; missing unique anchor: {anchor}")
for name in list(replacement)[1:]:
    if name in files:
        raise RuntimeError(f"File exists in source archive: {name}")
if b"youtubeBatchOutcomeMessage" not in replacement["lib/youtube_batch_publish_screen.dart"]:
    raise RuntimeError("Batch summary not connected to UI")
if b"token(forceRefresh:true)" not in replacement["lib/youtube_batch_publish_screen.dart"]:
    raise RuntimeError("Chrome preflight not connected to UI")

replacement["pubspec.yaml"] = files["pubspec.yaml"].replace(
    old_version, new_version
)
with ZipFile(tmp, "w") as out:
    for info, data in entries:
        out.writestr(info, replacement.get(info.filename, data))
    for path, data in replacement.items():
        if path not in files:
            out.writestr(path, data)
os.replace(tmp, src)
print("Packed v0.21.27+86: Chrome preflight, transparent 0-success reporting, reconnect UI")
