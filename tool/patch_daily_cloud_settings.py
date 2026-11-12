#!/usr/bin/env python3
"""Add an honest cloud automation entry point to the existing YouTube settings UI."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".daily-ui.tmp")
with ZipFile(src) as archive:
    entries=[(info,archive.read(info)) for info in archive.infolist()]
files={info.filename:blob for info,blob in entries}
pub=files["pubspec.yaml"].decode("utf-8")
old_version="version: 0.21.23+82"
new_version="version: 0.21.24+83"
if pub.count(old_version)!=1:
    raise RuntimeError("Unexpected app base version: "+pub[:150])

path="lib/youtube_settings.dart"
source=files[path].decode("utf-8")
if "import 'package:flutter/material.dart';" not in source:
    raise RuntimeError("YouTube settings imports changed")
if "import 'package:flutter/services.dart';" not in source:
    source=source.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';",
        1,
    )
anchor="        if(widget.clips.any((c)=>c.savedUri.isNotEmpty))...["
if source.count(anchor)!=1:
    raise RuntimeError("YouTube settings content anchor is missing or ambiguous")
info="""        const Divider(height: 28),
        const Text('매일 자동 검색·제작·업로드',
          style:TextStyle(fontSize:19,fontWeight:FontWeight.w600)),
        const SizedBox(height:7),
        const Text('위의 예약 공개는 이미 만들어진 영상을 업로드한 뒤 '
          'YouTube가 공개할 시각만 예약하는 기능이에요. '
          '매일 새 영상 검색부터 Gemini 편집, MP4 제작, 업로드까지 '
          '앱을 닫은 상태에서 실행하려면 별도의 GitHub 클라우드 자동화를 설정해야 합니다.',
          style:TextStyle(fontSize:12)),
        const SizedBox(height:8),
        OutlinedButton.icon(
          onPressed:locked?null:()async{
            const url='https://github.com/dmc0306/gpt-shorts-studio/'
              'actions/workflows/configure-daily-publish.yml';
            await Clipboard.setData(const ClipboardData(text:url));
            if(!mounted)return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text('클라우드 자동화 설정 링크를 복사했어요. '
                '브라우저에 붙여넣어 GitHub에서 예약 시각을 설정하세요.')));
          },
          icon:const Icon(Icons.content_copy),
          label:const Text('매일 자동 검색·업로드 설정 링크 복사'),
        ),
        const Text('새 클라우드 자동화는 기본적으로 꺼져 있으며, '
          'Gemini·Tavily·YouTube 연결과 재사용 권한 확인 뒤에만 동작해요.',
          style:TextStyle(fontSize:12)),
"""
source=source.replace(anchor,info+anchor,1)
updates={
    "pubspec.yaml":pub.replace(old_version,new_version).encode("utf-8"),
    path:source.encode("utf-8"),
}
assert "매일 자동 검색·제작·업로드" in source
assert "Clipboard.setData" in source
with ZipFile(tmp,"w") as output:
    for info,blob in entries:
        output.writestr(info,updates.get(info.filename,blob))
os.replace(tmp,src)
print("Packaged v0.21.24+83: YouTube settings clearly distinguishes scheduled visibility from daily cloud production")
