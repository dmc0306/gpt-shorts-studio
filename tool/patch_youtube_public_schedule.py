#!/usr/bin/env python3
"""Upgrade the existing private-only uploader to explicit public and YouTube-side scheduled publication.
Prepares several saved videos in one foreground batch; YouTube itself publishes each at publishAt.
"""
from pathlib import Path
from zipfile import ZipFile
import os

source=Path("shorts-studio-source.zip")
tmp=source.with_suffix(".public-schedule.tmp")
with ZipFile(source) as z:
    contents=[(info,z.read(info)) for info in z.infolist()]
base={info.filename:data for info,data in contents}
patch={}
def change(path,old,new):
    text=patch.get(path,base[path].decode("utf8"))
    n=text.count(old)
    if n!=1:raise RuntimeError(f"Expected one anchor in {path}, found {n}: {old[:110]!r}")
    patch[path]=text.replace(old,new,1)

version=base["pubspec.yaml"].decode("utf8")
if version.count("version: 0.21.21+80")!=1:
    raise RuntimeError("Unexpected base version: "+version[:160])
patch["pubspec.yaml"]=version.replace("version: 0.21.21+80","version: 0.21.22+81")

p="lib/youtube_channel.dart"
change(p,"    this.automatic = false,\n    this.madeForKids,",
"""    this.automatic = false,
    this.publishMode = 'private',
    this.cadenceHours = 24,
    this.publishHour = 18,
    this.publishMinute = 0,
    this.lastScheduledAtUtc = '',
    this.publicConsentChannel = '',
    this.madeForKids,""")
change(p,"  String authMode;\n  bool automatic, syntheticMedia;",
"""  String authMode;
  String publishMode, lastScheduledAtUtc, publicConsentChannel;
  int cadenceHours, publishHour, publishMinute;
  bool automatic, syntheticMedia;
  bool get publicApproved => channelId.isNotEmpty &&
      publicConsentChannel==channelId;
""")
change(p,"      automatic: data['automatic'] == true,\n      madeForKids:",
"""      automatic: data['automatic'] == true,
      publishMode: const ['private','public','scheduled'].contains(data['publishMode'])
        ? data['publishMode'] as String : 'private',
      cadenceHours: const [24,48,72,168].contains(data['cadenceHours'])
        ? data['cadenceHours'] as int : 24,
      publishHour: data['publishHour'] is int &&
          (data['publishHour'] as int)>=0 && (data['publishHour'] as int)<24
        ? data['publishHour'] as int : 18,
      publishMinute: data['publishMinute'] is int &&
          (data['publishMinute'] as int)>=0 && (data['publishMinute'] as int)<60
        ? data['publishMinute'] as int : 0,
      lastScheduledAtUtc: data['lastScheduledAtUtc'] as String? ?? '',
      publicConsentChannel: data['publicConsentChannel'] as String? ?? '',
      madeForKids:""")
change(p,"    if (!result.confirmed) result.automatic = false;",
"""    if (!result.confirmed ||
        (result.publishMode!='private'&&!result.publicApproved)){
      result.automatic = false;
    }""")
change(p,"    'automatic': automatic,\n    'madeForKids':",
"""    'automatic': automatic,
    'publishMode': publishMode,
    'cadenceHours': cadenceHours,
    'publishHour': publishHour,
    'publishMinute': publishMinute,
    'lastScheduledAtUtc': lastScheduledAtUtc,
    'publicConsentChannel': publicConsentChannel,
    'madeForKids':""")

p="lib/youtube_upload.dart"
change(p,"import 'package:http/http.dart' as http;",
"""import 'package:http/http.dart' as http;
import 'youtube_publish_plan.dart';""")
change(p,"    required bool syntheticMedia,\n    required void Function(double) onProgress,",
"""    required bool syntheticMedia,
    YouTubePublishPlan publishPlan=const YouTubePublishPlan.private(),
    required void Function(double) onProgress,""")
change(p,"      // Record the video ID before notifying the UI; retry then returns this ID.\n      await writeState({...state, 'videoId': id});",
"""      // Save the id before notifying; do not reupload on uncertain retries.
      final status=jsonDecode(response.body) as Map;
      final actual=status['status'] is Map?
          (status['status'] as Map)['privacyStatus'] as String?:null;
      await writeState({...state,'videoId':id,
        'actualPrivacy':actual??'unknown'});""")
change(p,"    } else {\n      if (title.trim().isEmpty ||",
"""    } else {
      if(publishPlan.publishAt!=null&&
         !publishPlan.publishAt!.isAfter(DateTime.now().toUtc().add(const Duration(minutes:10)))){
        throw const YouTubeFailure('예약 시각이 너무 가까워요. 다음 게시 시간으로 다시 예약해 주세요.');
      }
      if (title.trim().isEmpty ||""")
change(p,"            'status': {\n              'privacyStatus': 'private',\n              'selfDeclaredMadeForKids': madeForKids,\n              'containsSyntheticMedia': syntheticMedia,\n            },",
"""            'status':publishPlan.status(
              madeForKids:madeForKids,syntheticMedia:syntheticMedia),
""")
change(p,"      state.addAll({\n        'channelId': channelId,",
"""      state.addAll({
        'publishMode':publishPlan.mode,
        'requestedPrivacy':publishPlan.privacyStatus,
        if(publishPlan.publishAt!=null)
          'publishAt':publishPlan.publishAt!.toUtc().toIso8601String(),
        'channelId': channelId,""")

p="lib/youtube.dart"
change(p,"import 'youtube_upload.dart';",
"""import 'youtube_upload.dart';
import 'youtube_publish_plan.dart';""")
change(p,"  Future<void> setAutomatic(bool enabled) async {",
"""  Future<void> setPublishMode(String mode,{required bool approved}) async {
    if(uploading)throw const YouTubeFailure('업로드 중에는 공개 설정을 바꿀 수 없어요.');
    if(!const ['private','public','scheduled'].contains(mode)){
      throw const YouTubeFailure('공개 설정을 확인해 주세요.');
    }
    if(mode!='private'){
      if(!preferences.confirmed||!approved){
        throw const YouTubeFailure('채널·재사용 권한을 확인하고 공개 업로드에 동의해 주세요.');
      }
      preferences.publicConsentChannel=preferences.channelId;
    }else{
      preferences.publicConsentChannel='';
    }
    preferences.publishMode=mode;
    await saveSettings();
  }

  Future<void> setAutomatic(bool enabled) async {""")
change(p,"    if (enabled && !preferences.confirmed)\n      throw const YouTubeFailure('업로드 채널과 아동용 여부를 먼저 확인해 주세요.');",
"""    if (enabled && !preferences.confirmed)
      throw const YouTubeFailure('업로드 채널과 아동용 여부를 먼저 확인해 주세요.');
    if(enabled&&preferences.publishMode!='private'&&
        !preferences.publicApproved){
      throw const YouTubeFailure('전체 공개·예약 공개 동의와 채널 확인이 필요해요.');
    }""")
change(p,"      if (_cancelled) throw const YouTubeFailure('전송을 중단했어요.');\n      return await YouTubeUpload(",
"""      if (_cancelled) throw const YouTubeFailure('전송을 중단했어요.');
      YouTubePublishPlan publishing=const YouTubePublishPlan.private();
      // Existing resumable sessions keep their original privacy and publishAt.
      // Do not silently turn an older private upload into a public upload.
      if(previous['session'] is! String){
        if(preferences.publishMode!='private'&&!preferences.publicApproved){
          throw const YouTubeFailure('공개 업로드 동의를 다시 확인해 주세요.');
        }
        if(preferences.publishMode=='public'){
          publishing=const YouTubePublishPlan.public();
        }else if(preferences.publishMode=='scheduled'){
          final next=YouTubeCadence.nextUtc(
            now:DateTime.now(),
            intervalHours:preferences.cadenceHours,
            hour:preferences.publishHour,minute:preferences.publishMinute,
            previousUtc:DateTime.tryParse(preferences.lastScheduledAtUtc));
          publishing=YouTubePublishPlan.scheduled(next);
          // Reserve before network upload, preventing duplicate slots on retry
          // or process termination. Failed reservations can leave harmless gaps.
          preferences.lastScheduledAtUtc=next.toIso8601String();
          await saveSettings();
        }
      }
      return await YouTubeUpload(""")
change(p,"        syntheticMedia: preferences.syntheticMedia,\n        onProgress:",
"""        syntheticMedia: preferences.syntheticMedia,
        publishPlan:publishing,
        onProgress:""")
change(p,"        title: clip.headline.replaceAll(RegExp(r'\\s+'), ' ').trim(),",
"""        title: (clip.headline.trim().isNotEmpty?clip.headline:clip.name)
            .replaceAll(RegExp(r'\\s+'),' ').trim(),""")

p="lib/youtube_panel.dart"
change(p,"  String? videoId, error;",
"""  String? videoId,error,requestMode,scheduledAt;""")
change(p,"          videoId = state['videoId'] as String?;\n          pending =",
"""          videoId = state['videoId'] as String?;
          requestMode = state['publishMode'] as String?;
          scheduledAt = state['publishAt'] as String?;
          pending =""")
change(p,"          const Text('유튜브 비공개 업로드', style: TextStyle(fontSize: 18)),",
"""          const Text('유튜브 공개·예약 업로드',style:TextStyle(fontSize:18)),""")
change(p,"                ? '새 MP4 저장 후 자동 전송 켜짐'\n                : '자동 전송 꺼짐 · 저장한 MP4를 직접 올릴 수 있어요.',",
"""                ? '새 MP4 저장 시 ${youtube.preferences.publishMode=='scheduled'?'유튜브 예약 게시':youtube.preferences.publishMode=='public'?'전체 공개':'비공개'}로 자동 전송'
                : '자동 전송 꺼짐 · 저장한 MP4를 직접 올릴 수 있어요.',""")
change(p,"              '전송 완료 · 처리 상태는 YouTube Studio에서 확인\\nhttps://www.youtube.com/watch?v=$videoId',",
"""              '전송 완료 · ${requestMode=='scheduled'?'공개 예약 ${scheduledAt??''}':requestMode=='public'?'전체 공개 요청':'비공개 전송'}'
              '\\nYouTube Studio에서 실제 공개 상태를 확인하세요.'
              '\\nhttps://www.youtube.com/watch?v=$videoId',""")

p="lib/youtube_settings.dart"
change(p,"import 'youtube_upload.dart';",
"""import 'youtube_upload.dart';
import 'youtube_publish_plan.dart';
import 'youtube_batch_publish_screen.dart';
import 'model.dart';""")
change(p,"  const YouTubeSettingsScreen({super.key});",
"""  const YouTubeSettingsScreen({super.key,this.clips=const []});
  final List<Clip> clips;""")
change(p,"  @override Widget build(BuildContext context) => Scaffold(",
"""  Future<void> selectMode(String mode)async{
    if(mode=='private'){
      await run(()=>youtube.setPublishMode('private',approved:true));
      return;
    }
    if(!youtube.preferences.confirmed){
      setState(()=>error='먼저 실제 채널과 아동용 여부를 확인해 주세요.');
      return;
    }
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(mode=='scheduled'?'자동 예약 공개 활성화':'전체 공개 업로드 활성화'),
      content:Text('대상 채널: ${youtube.preferences.channelTitle}\\n\\n'
        '새 MP4를 ${mode=='scheduled'?'예약한 날짜에 전체 공개':'업로드 직후 전체 공개'}합니다. '
        '유튜브에 이미 올라간 과거 비공개 영상은 자동으로 공개 전환되지 않습니다.\\n\\n'
        '직접 제작했거나 게시·재이용 권한을 가진 영상만 업로드하고 '
        '기존 자막, 원제작자 및 저작권을 확인하겠습니다.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),
          child:const Text('확인하고 활성화')),
      ]));
    if(accepted!=true||!mounted)return;
    await run(()=>youtube.setPublishMode(mode,approved:true));
  }
  Future<void> pickPublishTime()async{
    final p=youtube.preferences;
    final picked=await showTimePicker(context:context,
      initialTime:TimeOfDay(hour:p.publishHour,minute:p.publishMinute));
    if(picked==null||!mounted)return;
    await run(()async{
      p.publishHour=picked.hour;
      p.publishMinute=picked.minute;
      await youtube.saveSettings();
    });
  }
  @override Widget build(BuildContext context) => Scaffold(""")
change(p,"        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('완성 MP4 자동 업로드'),\n          subtitle: const Text('수동 저장과 자동 제작의 새 완성본을 비공개로 전송해요. 공개·예약은 YouTube Studio에서 설정하세요.'),",
"""        const Divider(height: 28),
        const Text('업로드 공개 방식',style:TextStyle(fontSize:19,fontWeight:FontWeight.w600)),
        const SizedBox(height:8),
        const Text('새 MP4 공개 범위'),
        DropdownButton<String>(
          value:p.publishMode,
          isExpanded:true,
          items:const [
            DropdownMenuItem(value:'private',child:Text('비공개 (기본값)')),
            DropdownMenuItem(value:'public',child:Text('업로드 후 즉시 전체 공개')),
            DropdownMenuItem(value:'scheduled',child:Text('주기별 예약 공개')),
          ],
          onChanged:locked?null:(mode){if(mode!=null)selectMode(mode);},
        ),
        if(p.publishMode=='scheduled')...[
          const SizedBox(height:10),
          DropdownButtonFormField<int>(
            key:ValueKey('cadence_${p.cadenceHours}'),
            initialValue:p.cadenceHours,
            decoration:const InputDecoration(labelText:'공개 주기'),
            items:const [
              DropdownMenuItem(value:24,child:Text('매일')),
              DropdownMenuItem(value:48,child:Text('2일마다')),
              DropdownMenuItem(value:72,child:Text('3일마다')),
              DropdownMenuItem(value:168,child:Text('매주')),
            ],
            onChanged:locked?null:(interval)async{
              if(interval==null)return;
              await run(()async{p.cadenceHours=interval;await youtube.saveSettings();});
            },
          ),
          TextButton.icon(onPressed:locked?null:pickPublishTime,
            icon:const Icon(Icons.schedule_outlined),
            label:Text('게시 시각 ${p.publishHour.toString().padLeft(2,'0')}:'
              '${p.publishMinute.toString().padLeft(2,'0')} (휴대폰 현지시간)')),
          Builder(builder:(context){
            final next=YouTubeCadence.nextUtc(now:DateTime.now(),
              intervalHours:p.cadenceHours,hour:p.publishHour,minute:p.publishMinute,
              previousUtc:DateTime.tryParse(p.lastScheduledAtUtc)).toLocal();
            return Text('다음 자동 게시 예정: ${next.toString().substring(0,16)}');
          }),
          const Text('영상은 지금 YouTube에 비공개로 올리고, '
            '예약 날짜에 YouTube에서 자동 공개합니다. '
            '새 영상 자동 제작은 앱 실행 또는 제작 프로세스가 필요합니다.',
            style:TextStyle(fontSize:12)),
        ],
        if(widget.clips.any((c)=>c.savedUri.isNotEmpty))...[
          const SizedBox(height:10),
          OutlinedButton.icon(
            onPressed:locked?null:()=>Navigator.of(context).push(
              MaterialPageRoute(builder:(_)=>YouTubeBatchPublishScreen(clips:widget.clips))),
            icon:const Icon(Icons.queue_play_next),
            label:const Text('저장된 MP4 여러 개 공개·예약 업로드')),
        ],
        SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:const Text('완성 MP4 자동 업로드'),
          subtitle:const Text('켜면 앞으로 저장하는 MP4가 선택한 공개 방식으로 업로드돼요. '
            '이미 비공개로 올린 영상은 자동으로 공개되지 않습니다.'),""")

p="lib/main.dart"
change(p,"import 'youtube_settings.dart';",
"""import 'youtube_settings.dart';
import 'youtube_batch_publish_screen.dart';""")
change(p,"builder:(_)=>const YouTubeSettingsScreen()",
"""builder:(_)=>YouTubeSettingsScreen(clips:clips)""")
change(p,"IconButton(tooltip:'유튜브 채널 설정',",
"""IconButton(tooltip:'저장된 MP4 예약·공개 업로드',
  onPressed:busy?null:()=>Navigator.push(context,MaterialPageRoute(
    builder:(_)=>YouTubeBatchPublishScreen(clips:clips))),
  icon:const Icon(Icons.schedule_send_outlined)),
  IconButton(tooltip:'유튜브 채널 설정',""")

newfiles={
  "lib/youtube_publish_plan.dart":Path("tool/youtube_publish_plan.dart").read_bytes(),
  "lib/youtube_batch_publish_screen.dart":Path("tool/youtube_batch_publish_screen.dart").read_bytes(),
  "test/youtube_schedule_test.dart":Path("tool/youtube_schedule_tests.dart").read_bytes(),
}
for path in newfiles:
    if path in base:raise RuntimeError("Already contains "+path)
with ZipFile(tmp,"w") as output:
    for info,data in contents:
        value=patch.get(info.filename)
        output.writestr(info,data if value is None else value.encode("utf8"))
    for name,blob in newfiles.items():
        output.writestr(name,blob)
os.replace(tmp,source)
print("Packaged 0.21.22+81 YouTube public, scheduled and 20-item foreground batch uploads")
