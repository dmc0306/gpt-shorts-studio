import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'ai.dart';
import 'bridge.dart';
import 'model.dart';
import 'discovery.dart';
import 'tiktok_download.dart';
import 'original_text.dart';
import 'scene_selection.dart';
import 'overlay_renderer.dart';
import 'caption_layout.dart';
import 'youtube.dart';
import 'headline.dart';

/// A separate AOT entry point for Android WorkManager. No MaterialApp,
/// Navigator, main Activity, user gesture, or background Activity launch.
@pragma('vm:entry-point')
void dailyHeadlessMain() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(DailyHeadlessRunner().run());
}

class DailyHeadlessRunner {
  static const channel=MethodChannel('studio.local/daily_runner');
  static const maxCandidates=20;
  final log=<String>[];
  Future<void> step(String stage)async {
    log.add(stage);
    try{await channel.invokeMethod('progress',{'stage':stage});}catch(_){}
  }

  Future<void> run()async {
    bool success=false;
    String reason='배경 작업 시작 실패';
    try{
      final raw=await channel.invokeMethod<Map<dynamic,dynamic>>('settings')??{};
      final creators=(raw['creators'] as List? ?? [])
          .whereType<String>().map((e)=>e.toLowerCase().replaceFirst('@','')).toSet();
      if(creators.isEmpty)throw StateError('권리 확인된 영상 제작자가 없습니다.');
      await step('연결과 영상 재사용 권한 확인');
      final config=await Native.call<Map<dynamic,dynamic>>('loadAiSettings')??{};
      final geminiKey=(config['key'] as String? ?? '').trim();
      final searchKey=(config['searchKey'] as String? ?? '').trim();
      final model=(config['model'] as String? ?? GeminiCaptions.defaultModel).trim();
      if(geminiKey.isEmpty||searchKey.isEmpty) {
        throw StateError('Gemini/Tavily 키가 연결되지 않았습니다.');
      }
      final youtube=YouTube.instance;
      await youtube.loadSettings();
      if(youtube.preferences.authMode!='chrome'||
         !youtube.automatic||!youtube.preferences.confirmed||
         (youtube.preferences.publishMode!='private' &&
          !youtube.preferences.publicApproved)){
        throw StateError('Chrome 연결·채널 확인·자동 업로드 동의가 필요합니다.');
      }
      await youtube.initialize();
      if(!youtube.chrome.hasRefreshToken) {
        throw StateError('YouTube OAuth 갱신 권한이 없습니다.');
      }

      final state=await Native.call<Map<dynamic,dynamic>>('loadDailyHistory')??{};
      final used=(state['usedVideoIds'] as List? ?? [])
          .whereType<String>().toSet();
      final attempts=<String>{};
      final clips=await Native.load();
      int examined=0;
      final searches=creators.toList()..sort();
      final topics=MixedDiscovery.topics;

      for(final handle in searches){
        if(success||examined>=maxCandidates)break;
        for(final topic in topics){
          if(success||examined>=maxCandidates)break;
          await step('@$handle · $topic 새 영상 검색');
          final finder=MixedDiscovery();
          List<VideoCandidate> results=const [];
          try{
            results=await finder.discover(
              key:searchKey,
              excluded:{...used,...attempts},
              query:'site:tiktok.com/@$handle/video/ $topic',
              topic:topic,
              onStatus:(message){},
            );
          }catch(_){
            await step('검색 장애 · 다음 검색어로 진행');
          }finally{finder.cancel();}

          for(final candidate in results){
            if(success||examined>=maxCandidates)break;
            final canonical=MixedDiscovery.videoUrl(candidate.url);
            final matched=RegExp(r'^https://www\.tiktok\.com/@([a-zA-Z0-9._]+)/video/(\d+)$')
                .firstMatch(canonical??'');
            if(matched==null||matched.group(1)!.toLowerCase()!=handle)continue;
            final id=matched.group(2)!;
            if(used.contains(id)||!attempts.add(id))continue;
            examined++;
            TikTokDownloader? downloader;
            GeminiCaptions? gemini;
            Clip? clip;
            try{
              await step('새 영상 $examined/$maxCandidates · 다운로드 및 길이 검사');
              downloader=TikTokDownloader();
              final rawVideo=await downloader.download(
                candidate.url,(value,stage){},
                minDuration:5,maxDuration:60,
              );
              clip=Clip.fromJson(rawVideo);
              clip.url=canonical!;
              clip.category=topic;
              clip.crop=true;
              clip.start=0;
              clip.end=clip.duration;
              if(clip.duration<5||clip.duration>60)continue;
              final current=clip;

              await step('Gemini로 원본·장면·기존 자막 확인');
              gemini=GeminiCaptions();
              final draft=await gemini.generate(
                clip:current,key:geminiKey,model:model,
                assessEntertainment:true,selectHighlight:true,
                contentCategory:topic,
                onStatus:(message){},
              );
              if(!draft.quality.acceptable ||
                 draft.selection?.usable!=true ||
                 draft.entertainmentScore<55)continue;
              final selection=draft.selection!;
              final selectedDuration=selection.end-selection.start;
              if(selectedDuration<5||selectedDuration>30)continue;
              await step('선택 구간 원본 자막 OCR 검사');
              final scan=await Native.call<Map<dynamic,dynamic>>('scanOriginalText',{
                'path':current.path,
                'startMs':(selection.start*1000).round(),
                'endMs':(selection.end*1000).round(),
                'crop':true,
              })??{};
              if(scan['complete']!=true||
                 scan['cropped']!=true||
                 scan['scanStart'] is! num||
                 scan['scanEnd'] is! num||
                 ((scan['scanStart'] as num)-selection.start).abs()>.05||
                 ((scan['scanEnd'] as num)-selection.end).abs()>.05 ||
                 OriginalTextPolicy.hasOverlay(
                     scan,start:selection.start,end:selection.end)){
                continue;
              }
              current.start=selection.start;
              current.end=selection.end;
              current.headline=draft.headline;
              current.titleCandidates=draft.titles;
              current.timedCaptions=draft.captions;
              current.style=0;
              if(!validHeadline(current.headline))continue;

              // Lock the TikTok ID *before* YouTube accepts a resumable upload:
              // unknown outcomes must never cause the same video to be reuploaded.
              await Native.call('reserveDailySource',{'videoId':id});
              await step('상단·하단 제목과 장면별 자막으로 MP4 제작');
              final title=await renderOverlayPng(
                headline:current.headline,caption:'',style:current.style);
              final overlays=<Map<String,dynamic>>[];
              for(final t in current.timedCaptions){
                if(t.end<=current.start||t.start>=current.end)continue;
                overlays.add({
                  'startUs':((t.start-current.start)*1000000).round(),
                  'endUs':((t.end-current.start)*1000000).round(),
                  'topPx':placeCaption(t.text,cue:t,clip:current).stripTop,
                  'png':await renderOverlayPng(
                    headline:'',caption:t.text,style:current.style,
                    subtitleOnly:true,cue:t,clip:current),
                });
              }
              final uri=await Native.call<String>('export',{
                'path':current.path,
                'overlay':title,
                'timedOverlays':overlays,
                'startMs':(current.start*1000).round(),
                'endMs':(current.end*1000).round(),
                'mute':current.mute,'crop':current.crop,
              });
              if(uri==null||uri.isEmpty)throw StateError('MP4 제작 실패');
              current.savedUri=uri;
              current.savedAt=DateTime.now().toIso8601String();
              clips.insert(0,current);
              await Native.save(clips);

              await step('확인된 YouTube 채널로 완성 MP4 업로드');
              final videoId=await youtube.uploadClip(current);
              if(videoId.isEmpty)throw StateError('YouTube 업로드 ID 없음');
              await Native.call('dailyUploadSuccess',{
                'sourceId':id,'youtubeVideoId':videoId,
              });
              success=true;
              reason='영상 1개 업로드 접수 · YouTube ID $videoId';
              break;
            }catch(_){
              await step('검증 또는 제작 실패 · 후보 제외');
            }finally{
              downloader?.cancel();
              gemini?.cancel();
            }
          }
        }
      }
      if(!success)reason='검증을 통과한 새 영상이 없거나 업로드에 실패했습니다.';
    }catch(e){
      reason='예약 작업 설정·연결 또는 백그라운드 환경 오류';
    }finally{
      try{
        await channel.invokeMethod('finished',{
          'success':success,'message':reason,
          'stages':log.take(80).toList(),
        });
      }catch(_){}
    }
  }
}
