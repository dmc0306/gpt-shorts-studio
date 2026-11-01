#!/usr/bin/env python3
"""Secure Android image share for visual reverse search of real video frames."""
from zipfile import ZipFile
from pathlib import Path
import os
source=Path('shorts-studio-source.zip')
tmp=source.with_suffix('.lens.zip')
with ZipFile(source) as z:entries=[(item,z.read(item)) for item in z.infolist()]
files={item.filename:blob for item,blob in entries}
old_version='version: 0.21.7+66'
pub=files['pubspec.yaml'].decode('utf8')
if pub.count(old_version)!=1:raise RuntimeError('Unexpected app version '+pub[:110])
ui=Path('tool/benchmark_ui.dart').read_text()
extractor=Path('tool/BenchmarkFrameExtractor.kt').read_text()
if 'shareFrameToLens' not in ui or 'originalContent' not in extractor:
    raise RuntimeError('Frame-sharing changes missing')
main=files['native/android/MainActivity.kt'].decode('utf8')
manifest=files['native/android/AndroidManifest.xml'].decode('utf8')
bootstrap=files['tool/bootstrap.py'].decode('utf8')
def replace_once(text,before,after,label):
    if text.count(before)!=1:raise RuntimeError(f'{label}: expected one insertion point, got {text.count(before)}')
    return text.replace(before,after,1)
main=replace_once(main,'import androidx.documentfile.provider.DocumentFile',
'import androidx.documentfile.provider.DocumentFile\nimport androidx.core.content.FileProvider\nimport android.content.ClipData','MainActivity')
handler="""            "benchmarkShareFrame" -> {
                val encoded=call.argument<String>("content")?:""
                require(encoded.length in 160..1400000){"검색 장면 이미지 크기가 올바르지 않아요."}
                val bytes=Base64.decode(encoded,Base64.DEFAULT)
                require(bytes.size in 128..1000000 &&
                    (bytes[0].toInt() and 255)==255 &&
                    (bytes[1].toInt() and 255)==216){"JPEG 프레임만 공유해 주세요."}
                val folder=File(cacheDir,"lens-frames")
                check(folder.exists()||folder.mkdirs()){"프레임 공유 폴더 오류"}
                val now=System.currentTimeMillis()
                folder.listFiles()?.forEach { f ->
                    if(f.isFile && (now-f.lastModified()>3600000)) f.delete()
                }
                val output=File(folder,"frame_"+UUID.randomUUID().toString()+".jpg")
                output.writeBytes(bytes)
                val uri=FileProvider.getUriForFile(this,
                    "$packageName.benchmarkframeprovider",output)
                val send=Intent(Intent.ACTION_SEND).apply {
                    type="image/jpeg"
                    putExtra(Intent.EXTRA_STREAM,uri)
                    clipData=ClipData.newRawUri("Short Studio 검색 장면",uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send,
                    "이미지 검색 앱 선택 (Google Lens 등)"))
                r.success(null)
            }
"""
main=replace_once(main,'            "benchmarkFingerprintImage" -> async(r) {',
handler+'            "benchmarkFingerprintImage" -> async(r) {','MainActivity')
provider='''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="APPLICATION_ID_PLACEHOLDER.benchmarkframeprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/benchmark_frame_paths" />
        </provider>
'''
provider=provider.replace('APPLICATION_ID_PLACEHOLDER',chr(36)+'{applicationId}')
manifest=replace_once(manifest,'        <meta-data android:name="flutterEmbedding"',
provider+'        <meta-data android:name="flutterEmbedding"','AndroidManifest')
paths='''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="image_search_frames" path="lens-frames/" />
</paths>
'''
# bootstrap already copies AndroidManifest; add only scoped FileProvider XML.
bootstrap=replace_once(bootstrap,
"shutil.copy2(root/'native/android/network_security_config.xml',dest)",
"shutil.copy2(root/'native/android/network_security_config.xml',dest)\n"
"frame_share_xml=app/'src/main/res/xml/benchmark_frame_paths.xml'\n"
"frame_share_xml.parent.mkdir(parents=True,exist_ok=True)\n"
"shutil.copy2(root/'native/android/benchmark_frame_paths.xml',frame_share_xml)",
'bootstrap')
updated={
 'lib/benchmark_ui.dart':ui.encode('utf8'),
 'native/android/BenchmarkFrameExtractor.kt':extractor.encode('utf8'),
 'native/android/MainActivity.kt':main.encode('utf8'),
 'native/android/AndroidManifest.xml':manifest.encode('utf8'),
 'native/android/benchmark_frame_paths.xml':paths.encode('utf8'),
 'tool/bootstrap.py':bootstrap.encode('utf8'),
 'pubspec.yaml':pub.replace(old_version,'version: 0.21.8+67').encode('utf8'),
}
assert main.count('"benchmarkShareFrame"')==1
assert manifest.count('.benchmarkframeprovider')==1
with ZipFile(tmp,'w') as z:
    for item,blob in entries:z.writestr(item,updated.pop(item.filename,blob))
    if set(updated)!={'native/android/benchmark_frame_paths.xml'}:
        raise RuntimeError('Unaccounted path '+str(updated.keys()))
    for path,blob in updated.items():z.writestr(path,blob)
os.replace(tmp,source)
print('0.21.8+67: scoped Android image sharing with full-resolution scene, manual visual search fallback')
