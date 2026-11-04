import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'benchmark_stream.dart';
import 'benchmark_oneclick.dart';
import 'benchmark_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'benchmark_data.dart';
import 'bridge.dart';
import 'editor.dart';
import 'model.dart';
import 'tiktok_download.dart';
import 'vision_reverse.dart';

class BenchmarkScreen extends StatefulWidget {
 const BenchmarkScreen({super.key,required this.clips,required this.onSave});
 final List<Clip> clips; final Future<void> Function() onSave;
 @override State<BenchmarkScreen> createState()=>_BenchmarkState();
}
class _BenchmarkState extends State<BenchmarkScreen>{
 final keyText=TextEditingController(),visionKeyText=TextEditingController(),channelText=TextEditingController(),originText=TextEditingController();
 BenchState state=BenchState();
 String message='';
 final framePreviews=<String,List<Uint8List>>{};
 /// In-memory reference hashes needed for an optional local-file check.
 /// Raw video and credentials are not persisted in history.
 final referenceFrames=<String,List<dynamic>>{};
 bool busy=false,loading=true;
 String? activeVideoId;
 final shownAllCandidates=<String>{};
 bool cancelled=false;
 OneClickExplorer? activeExplorer;
 BenchmarkStreamResolver? activeStream;
 void stopSearch(){
   if(!busy)return;
   cancelled=true;
   activeExplorer?.cancel();
   activeStream?.cancel();
   Native.call('cancelTextScan');
   report('중단 요청을 전달했어요. 현재 영상 처리 종료 후 버튼이 복구됩니다.');
 }
 @override void initState(){super.initState();load();}
 @override void dispose(){keyText.dispose();visionKeyText.dispose();channelText.dispose();originText.dispose();super.dispose();}
 Future<void> load()async{
  try{
   final raw=await Native.call<String>('loadBenchmarkState');
   if(raw!=null&&raw.isNotEmpty)state=BenchState.fromJson(jsonDecode(raw) as Map);
   keyText.text=await Native.call<String>('benchmarkApiKey')??'';
   visionKeyText.text=await Native.call<String>('benchmarkVisionKey')??'';
   // Expire the previous text-search origin suggestions; keep user-added links.
   for(final id in state.origins.keys.toList()){
     state.origins[id]=state.origins[id]!.where((c)=>
       c.source=='실제 동영상 교차확인'||
       c.source=='실제 영상 미검증 후보'||
       c.source=='자막 검출 후보'||
       c.source=='자막 확인 필요 후보'||
       c.source=='연관 페이지만 확인'||
       c.source=='검증되지 않은 검색 후보'||
       c.source=='직접 추가').toList();
     if(!state.origins[id]!.any((c)=>c.url==state.chosen[id]))state.chosen.remove(id);
   }
  }catch(_){message='이전 소재 기록을 불러오지 못했어요.';}
  if(mounted)setState(()=>loading=false);
 }
 Future<void> save()=>Native.call('saveBenchmarkState',{'json':jsonEncode(state.toJson())});
 void report(String s){
   if(activeVideoId!=null)state.diagnostics[activeVideoId!]=s;
   if(mounted)setState(()=>message=s);
 }
 Future<void> run(Future<void> Function() action)async{
  if(busy)return;setState(()=>busy=true);
  try{await action();await save();}catch(e){report('작업 실패: $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> exportBackup()async{
   try{
     // Exports only BenchState; encrypted API credentials and downloaded
     // media are intentionally not included in this copyable JSON.
     final content=jsonEncode(state.toJson());
     await Clipboard.setData(ClipboardData(text:content));
     if(!mounted)return;
     await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
       title:const Text('검색 기록 백업 복사 완료'),
       content:const Text('채널, 선정 영상, 원본 후보 및 제외 기록을 클립보드에 복사했어요. '
         '메모나 개인 저장소에 붙여넣어 보관하세요. 앱을 삭제하면 앱 내부 기록은 지워질 수 있어요. '
         'API 키와 영상 파일은 백업에 포함되지 않습니다.'),
       actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('확인'))]));
   }catch(e){report('백업 복사 실패: $e');}
 }
 Future<void> restoreBackup()async{
   if(busy)return;
   try{
     final clip=await Clipboard.getData(Clipboard.kTextPlain);
     final raw=clip?.text?.trim()??'';
     if(raw.isEmpty||raw.length>1000000)throw const FormatException('클립보드에 유효한 백업 텍스트가 없습니다.');
     final decoded=jsonDecode(raw);
     if(decoded is! Map||decoded['channels'] is! Map||decoded['top'] is! Map){
       throw const FormatException('Short Studio 검색 기록 백업이 아닙니다.');
     }
     final candidate=BenchState.fromJson(decoded);
     if(!mounted)return;
     final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
       title:const Text('검색 기록 복원'),
       content:Text('백업에서 채널 ${candidate.channels.length}개와 '
         '선정 기록 ${candidate.selected.length}개를 찾았어요.\\n\\n'
         '현재 앱의 검색 기록을 이 백업으로 교체합니다. '
         '저장된 API 키와 제작한 영상 파일에는 영향을 주지 않습니다.'),
       actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('기록 복원'))]));
     if(confirm!=true||!mounted)return;
     setState((){
       state=candidate;
       framePreviews.clear();
       referenceFrames.clear();
       shownAllCandidates.clear();
     });
     await save();
     report('검색 기록을 복원했어요. API 키가 없다면 다시 등록해 주세요.');
   }catch(e){report('백업 복원 실패: $e');}
 }
 Future<void> removeChannel(String id,String title)async{
   if(busy)return;
   final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
     title:const Text('채널을 목록에서 제외할까요?'),
     content:Text('「$title」을 수집 대상에서 숨깁니다. '
       '이미 검색한 후보와 제작 파일은 삭제하지 않습니다.'),
     actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
       FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('채널 제외'))]));
   if(accepted!=true||!mounted)return;
   setState(()=>state.channels.remove(id));
   await save();
   if(!mounted)return;
   ScaffoldMessenger.of(context).hideCurrentSnackBar();
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
     content:Text('「$title」 채널을 제외했어요.'),
     action:SnackBarAction(label:'실행 취소',onPressed:(){
       if(!mounted)return;
       setState(()=>state.channels[id]=title);
       save();
     })));
 }
 Future<void> drawRandom({bool searchImmediately=false})async{
   if(busy)return;
   final pool=<BenchVideo>[];
   for(final key in state.channels.keys){
     for(final video in state.top[key]??<BenchVideo>[]){
       if(video.eligibleForAutoSearch&&!state.seen.contains(video.id))pool.add(video);
     }
   }
   if(pool.isEmpty){
     report('선정할 새 쇼츠가 없어요. 상단의 영상 목록 갱신을 실행해 주세요.');
     return;
   }
   final video=pool[Random.secure().nextInt(pool.length)];
   setState((){
     state.selected..clear()..add(video.id);
     state.seen.add(video.id);
   });
   await save();
   if(searchImmediately)await search(video,continuous:true);
 }
 Future<void> scan()async=>run(()async{
  final client=BenchApi(keyText.text.trim());
  var ok=0;
  try{
   for(final entry in state.channels.entries.toList()){
    report('분석 ${ok+1}/${state.channels.length}: ${entry.value}');
    try{
     final x=await client.ranking(entry.key,progress:(n)=>report('${entry.value}: $n 페이지 읽는 중'));
     state.channels[entry.key]=x.name;state.top[entry.key]=x.top;
     state.scanned[entry.key]=x.scanned;state.complete[entry.key]=x.complete;
     ok++;
    }catch(e){state.complete[entry.key]=false;report('${entry.value}: $e');}
    await save();
   }
   report('$ok개 채널 분석 성공. 최신 조회수 상위 50개씩 저장했어요. 일부 수집된 채널은 결과가 불완전할 수 있어요.');
  }finally{client.close();}
 });
 Future<void> search(BenchVideo v,{bool manual=false,bool continuous=false})async{
  if(busy)return;
  if(!manual&&!v.eligibleForAutoSearch){
    report('롱폼/긴 영상 제외: ${v.duration}초 · 자동 검색은 60초 이하 영상만 지원해요.');
    return;
  }
  if(visionKeyText.text.trim().isEmpty&&keyText.text.trim().isEmpty){
    report('Cloud Vision API 키를 입력해 주세요.');return;
  }
  cancelled=false;
  if(mounted)setState(()=>activeVideoId=v.id);
  try{
  await run(()async{
    List<dynamic>? frames;
    if(manual){
      report('기기에 있는 벤치마킹 영상 선택');
      frames=await Native.call<List<dynamic>>('benchmarkPickFrames');
      if(frames==null){report('파일 선택을 취소했어요.');return;}
    }else{
      final path=await Native.call<String>('benchmarkStreamCachePath',{'id':v.id});
      if(path==null)throw StateError('임시 영상 경로를 가져오지 못했어요.');
      try{
        report('선정된 영상 스트림 확보 중');
        activeStream=BenchmarkStreamResolver();
        await activeStream!.download(v.id,path,(message)=>report(message));
        if(cancelled)throw const OneClickCancelled();
        frames=await Native.call<List<dynamic>>('benchmarkExtractFramesFromCache',{'id':v.id});
      }finally{
        activeStream=null;
        try{final f=File(path);if(await f.exists())await f.delete();}catch(_){}
      }
    }
    if(frames==null||frames.isEmpty){report('영상 프레임 추출 실패');return;}
    referenceFrames[v.id]=frames;
    final previews=<Uint8List>[];
    for(final frame in frames){
      if(frame is Map&&frame['content'] is String){
        previews.add(base64Decode(frame['content'] as String));

      }
    }
    if(mounted)setState((){
      framePreviews[v.id]=previews;
    });
    if(!manual&&frames.first is Map){
      final meta=frames.first as Map;
      final millis=(meta['durationMs'] as num?)?.toInt()??0;
      final width=(meta['videoWidth'] as num?)?.toInt();
      final height=(meta['videoHeight'] as num?)?.toInt();
      if(!BenchmarkDuration.isShortGeometry((millis/1000).round(),width,height)){
        report('유튜브 롱폼/가로 영상 제외 · 세로형 또는 정사각형 60초 이하만 자동 탐색해요.');
        return;
      }
    }
    report('한국어+영문 OCR 자막 검사 · 길이 ±10%(최소 ±2초) · 60초 이하 세로형 · 검색 장면 ${previews.length}장');
    final key=visionKeyText.text.trim().isNotEmpty?visionKeyText.text.trim():keyText.text.trim();
    final batches=OneClickExplorer.frameBatches(frames,continuous:continuous);
    final reviewed=<String>{
      ...(state.rejected[v.id]??<String>{}),
      ...(state.captioned[v.id]??<String>{}),
    };
    final collected=<String,CandidateCheck>{};
    var totalInspected=0;
    var roundsDone=0;
    var noDirectEvidenceRounds=0;
    var lastDiagnostic='';
    for(final batch in batches){
      if(cancelled)throw const OneClickCancelled();
      roundsDone++;
      report(continuous
        ?'연속찾기 $roundsDone/${batches.length} · 다른 장면 조합 검사 중 · 중단 버튼으로 종료 가능'
        :'원본 후보 검색 중');
      final explorer=OneClickExplorer(key,(message){
        if(!cancelled)report(continuous
          ?'연속찾기 $roundsDone/${batches.length} · $message':message);
      },youtubeApiKey:keyText.text.trim(),benchmarkSeconds:v.duration,
        ignoredUrls:reviewed);
      activeExplorer=explorer;
      final attempt=await explorer.run(v.id,batch);
      if(cancelled)throw const OneClickCancelled();
      totalInspected+=attempt.inspected;
      lastDiagnostic=attempt.diagnostic;
      for(final check in attempt.results){
        reviewed.add(check.origin.url); // do not spend quota on the same candidate again
        collected.putIfAbsent(check.origin.url,()=>check);
      }
      if(attempt.results.any((c)=>c.origin.source=='이미지 직접일치 후보')){
        noDirectEvidenceRounds=0;
      }else{
        noDirectEvidenceRounds++;
      }
      // An exact frame + subtitle-screened video match ends the loop, even
      // when its stream cannot be exported to an editor automatically.
      if(attempt.match!=null){
        report('실제 영상 장면 일치 · 연속찾기 자동 종료');
        break;
      }
      // No index evidence across two distinct crops: do not waste another
      // 4 expensive Cloud Vision requests on essentially the same video.
      if(continuous&&noDirectEvidenceRounds>=2){
        lastDiagnostic+=' · 서로 다른 이미지 조합 2회에서 직접 일치 근거가 없어 조기 종료';
        report('이미지 검색 근거 0 · 반복 검색 조기 종료 · 다른 벤치마킹 쇼츠를 선택해 주세요.');
        break;
      }
    }
    activeExplorer=null;
    final result=OneClickResult(collected.values.toList(),total:collected.length,
      inspected:totalInspected,
      diagnostic:continuous
        ?'연속찾기 $roundsDone/${batches.length}회 · 서로 다른 후보 ${collected.length}건 · $lastDiagnostic'
        :lastDiagnostic);
    state.diagnostics[v.id]=result.diagnostic;
    if(cancelled)throw const OneClickCancelled();
    final visible=<BenchOrigin>[];
    for(final item in result.results){
      final prefix=switch(item.status){
        'checked'=>'검증됨 · 자막 의심 미검출',
        'overlay'=>'자막 있음 · 기존 편집 글자 감지',
        'caption_possible'=>'확인 보류 · 화면 글자 감지',
        'unrelated'=>'제외 · 실제 영상 불일치',
        'duration'=>'제외 · 영상 길이 불일치 또는 확인 불가',
        'longform'=>'제외 · 유튜브 롱폼/가로 영상',
        'weak'=>'관련 페이지 참고용 · 영상 미검증',
        'unsupported'=>'실제 영상 확인 필요 · 자동 검사 미지원',
        'unverified'=>'실제 영상 확인 필요 · 검사 한도 초과',
        'error'=>'영상 검사 실패 · 원본 여부 미확인',_=>'확인 필요'
      };
      visible.add(BenchOrigin(item.origin.url,'$prefix · ${item.detail}',
        item.status=='checked'?'실제 동영상 교차확인':
        item.status=='weak'?'연관 페이지만 확인':
        item.status=='overlay'?'자막 검출 후보':
        item.status=='caption_possible'?'자막 확인 필요 후보':
        '실제 영상 미검증 후보'));
    }
    // Preserve user-supplied original links across future image searches.
    final manualSources=(state.origins[v.id]??<BenchOrigin>[])
        .where((x)=>x.source=='직접 추가').toList();
    state.origins[v.id]=[...manualSources,
      ...visible.where((x)=>!manualSources.any((m)=>m.url==x.url))];
    final confirmed=state.confirmed[v.id];
    if(confirmed!=null){
      state.chosen[v.id]=confirmed;
    }else{
      state.chosen.remove(v.id);
    }
    await save();
    final match=result.match;
    if(match!=null)state.chosen[v.id]=match.origin.url;
    final best=result.best;
    if(best?.clip!=null){
      state.chosen[v.id]=best!.origin.url;
      report('원본 영상 장면 교차확인 · 추가 자막 의심 미검출 · 기존 편집기를 엽니다.');
      final imported=best.clip!;
      final original=Clip(id:imported.id,name:v.title,path:imported.path,
        thumbnail:imported.thumbnail,duration:imported.duration,
        videoWidth:imported.videoWidth,videoHeight:imported.videoHeight,
        creator:v.channel,category:'기타',url:best.origin.url,aiContext:{
          'benchVideoId':v.id,'benchmarkVideo':v.url,
          'originalUrl':best.origin.url,'oneClickValidation':'frame-match-and-ocr',
        });
      if(!widget.clips.any((c)=>c.id==original.id)){
        widget.clips.insert(0,original);
        await widget.onSave();
      }
      await save();
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>EditorScreen(
        clip:original,onSave:widget.onSave,autoGenerateOnOpen:true)));
      report('자동 확인된 후보를 편집기로 연결했어요. 게시 전 원본·기존 자막 여부를 최종 확인해 주세요.');
    }else if(match!=null){
      report('영상 장면·자막 검증은 통과했지만 자동 파일 확보가 불가능해요. 아래의 확인된 원본 링크로 직접 검토해 주세요.');
    }else{
      report('${result.diagnostic} 일치 원본 미확인 · 후보를 확인하거나 나중에 다시 탐색할 수 있어요.');
    }
  });
  }finally{
    activeExplorer=null;
    activeStream=null;
    if(mounted)setState(()=>activeVideoId=null);
  }
 }
 Future<void> shareFrameToLens(BenchVideo v,int index)async{
   // Lens gets exactly the same OCR-screened crop as Cloud Vision.
   // Never substitute the uncropped video frame containing added captions.
   final frames=framePreviews[v.id];
   if(frames==null||index>=frames.length)return;
   try{
     await Native.call('benchmarkShareFrame',
       {'content':base64Encode(frames[index])});
   }catch(e){
     report('이미지 검색 앱으로 공유하지 못했어요: $e');
   }
 }
 Future<void> addOrigin(BenchVideo v)async{
  originText.clear();
  final entered=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
   title:const Text('원본 출처 직접 추가'),
   content:TextField(controller:originText,keyboardType:TextInputType.url,
    decoration:const InputDecoration(labelText:'원본 게시물 HTTPS URL')),
   actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('취소')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,originText.text),child:const Text('추가'))]));
  if(entered==null)return;
  final clean=normalOrigin(entered);
  if(clean==null){report('지원하지 않는 URL입니다. TikTok, Instagram, YouTube의 개별 게시물 주소를 입력하세요.');return;}
  await run(()async{
   final list=state.origins.putIfAbsent(v.id,()=>[]);
   if(!list.any((c)=>c.url==clean))list.insert(0,BenchOrigin(clean,'직접 입력한 후보 · 직접 원제작자 확인 필요','직접 추가'));
  });
 }
 Future<void> open(String url)async{
  try{await Native.call('openBenchmarkLink',{'url':url});}
  catch(_){report('브라우저에서 링크를 열 수 없어요.');}
 }
 Future<void> create(BenchVideo v)async{
  if(busy)return;
   final url=state.chosen[v.id];
   if(url==null){report('먼저 사용할 원본 게시물을 선택해 주세요.');return;}
  final fromTikTok=tiktokUrl(url)!=null;
  final mode=await showModalBottomSheet<String>(context:context,showDragHandle:true,
   builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),
    child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
     children:[const Text('원본 확보 → 기존 쇼츠 템플릿',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      const SizedBox(height:10),
             const Text('원본 후보를 선택한 다음 기기에 보유한 파일 또는 TikTok 영상을 연결하세요.'),
      const SizedBox(height:10),
      FilledButton(onPressed:()=>Navigator.pop(ctx,'file'),child:const Text('기기 MP4 원본 선택')),
      if(fromTikTok)OutlinedButton(onPressed:()=>Navigator.pop(ctx,'tiktok'),child:const Text('TikTok 영상 가져오기'))]))));
  if(mode==null)return;
  setState(()=>busy=true);
  try{
   Clip clip;
   final existing=widget.clips.where((c)=>c.aiContext['benchVideoId']==v.id&&c.ready).toList();
   if(existing.isNotEmpty){clip=existing.first;}
   else{
    Clip imported;
    if(mode=='file'){
     final raw=await Native.call<Map<dynamic,dynamic>>('pickVideo');
     if(raw==null){report('원본 선택을 취소했어요.');return;}
     imported=Clip.fromJson(Map<String,dynamic>.from(raw));
    }else{
     final task=TikTokDownloader();
     try{imported=Clip.fromJson(await task.download(url,(value,stage)=>report(stage),minDuration:5,maxDuration:180));}
     finally{task.cancel();}
    }
    clip=Clip(id:imported.id,name:v.title,path:imported.path,
     thumbnail:imported.thumbnail,duration:imported.duration,
     videoWidth:imported.videoWidth,videoHeight:imported.videoHeight,
     creator:v.channel,category:'기타',url:url,aiContext:{
       'benchVideoId':v.id,'benchmarkVideo':v.url,
       'originalUrl':url});
    widget.clips.insert(0,clip);await widget.onSave();
   }
   await save();
   if(!mounted)return;
   await Navigator.push(context,MaterialPageRoute(builder:(_)=>EditorScreen(
     clip:clip,onSave:widget.onSave,autoGenerateOnOpen:true)));
   report('기존 편집기에서 제목·자막을 확인하고 MP4를 저장할 수 있어요.');
  }catch(e){report('원본 가져오기/편집 실패: $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }

 Future<void> rejectOrigin(BenchVideo v,BenchOrigin origin,{required bool captioned})async{
   if(busy)return;
   setState((){
     final target=captioned?state.captioned:state.rejected;
     target.putIfAbsent(v.id,()=><String>{}).add(origin.url);
     state.origins[v.id]?.removeWhere((candidate)=>candidate.url==origin.url);
     if(state.chosen[v.id]==origin.url)state.chosen.remove(v.id);
     if(state.confirmed[v.id]==origin.url)state.confirmed.remove(v.id);
     if(state.matchedByUser[v.id]==origin.url){
       state.matchedByUser.remove(v.id);
       state.localSceneChecks.remove(v.id);
     }
   });
   await save();
   report(captioned
     ?'자막이 포함된 후보로 제외했어요. 이 주소는 다음 검색에서 건너뛰어요.'
     :'원본이 아닌 후보로 제외했어요. 이 주소는 다음 검색에서 건너뛰어요.');
 }
 Future<void> confirmFootageMatch(BenchVideo v,BenchOrigin origin)async{
   if(busy)return;
   final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
     title:const Text('같은 영상이라는 점을 확인했나요?'),
     content:Text('TikTok 링크의 장면이 기준 YouTube 쇼츠와 동일하다고 '
       '직접 확인한 사실만 저장해요.\\n\\n'
       '• 자동 프레임 검사 통과를 의미하지 않습니다.\\n'
       '• 기존 자막이 없는지는 아직 모릅니다.\\n'
       '• 원제작자와 이용 권한도 별도로 확인해야 합니다.\\n\\n'
       '${origin.url}'),
     actions:[
       TextButton(onPressed:()=>Navigator.pop(ctx,false),
         child:const Text('취소')),
       FilledButton(onPressed:()=>Navigator.pop(ctx,true),
         child:const Text('같은 영상으로 기록')),
     ]));
   if(accepted!=true||!mounted)return;
   setState((){
     state.matchedByUser[v.id]=origin.url;
     state.localSceneChecks.remove(v.id);
     state.rejected[v.id]?.remove(origin.url);
     state.captioned[v.id]?.remove(origin.url);
   });
   await save();
   report('이 TikTok 게시물을 같은 영상으로 기록했어요. 다운로드 오류 10204와 '
     '무관하게 검색 성공 사례는 보존하지만, 자동 검증·자막 없음으로 표시하지 않아요.');
 }
 Future<void> verifyCandidateFromFile(BenchVideo v,BenchOrigin origin)async{
   if(busy)return;
   cancelled=false;
   if(mounted)setState(()=>activeVideoId=v.id);
   try{
     await run(()async{
       var refs=referenceFrames[v.id];
       if(refs==null||refs.length<3){
         report('기준 쇼츠의 장면 정보 확보 중');
         final path=await Native.call<String>('benchmarkStreamCachePath',{'id':v.id});
         if(path==null)throw StateError('기준 영상 임시 경로 확보 실패');
         try{
           activeStream=BenchmarkStreamResolver();
           await activeStream!.download(v.id,path,(m)=>report(m));
           if(cancelled)throw const OneClickCancelled();
           refs=await Native.call<List<dynamic>>('benchmarkExtractFramesFromCache',{'id':v.id});
           if(refs==null||refs.length<3)throw StateError('기준 영상의 비교 장면 부족');
           referenceFrames[v.id]=refs;
         }finally{
           activeStream=null;
           try{final file=File(path);if(await file.exists())await file.delete();}catch(_){}
         }
       }
       if(cancelled)throw const OneClickCancelled();
       report('TikTok 후보를 휴대폰에 합법적으로 보유한 경우, 해당 영상 파일을 선택해 주세요.');
       final sample=await Native.call<List<dynamic>>('benchmarkPickFrames');
       if(sample==null){report('후보 영상 파일 선택을 취소했어요.');return;}
       final proof=LocalVideoProof.compare(refs!,sample);
       if(!LocalVideoProof.strong(proof)){
         report(proof.lengthOk
           ?'로컬 영상 장면 비교 미통과 · 순서대로 유사한 장면 ${proof.matched}개 · '
            '최소 3개 필요. 자막 위치나 편집 차이로 일치 영상도 실패할 수 있어요.'
           :'후보와 기준 쇼츠의 영상 길이가 달라 자동 비교를 보류했어요.');
         return;
       }
       if(!mounted)return;
       final tied=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
         title:const Text('영상 장면 비교 통과'),
         content:Text('휴대폰에서 선택한 파일은 기준 쇼츠와 시간 순서가 맞는 '
           '서로 다른 장면 ${proof.matched}개가 일치했어요.\\n\\n'
           '선택한 파일이 현재 TikTok 게시물에서 얻은 영상인지 '
           '직접 확인해 주세요. 자동으로 두 대상을 연결할 수는 없습니다.\\n\\n'
           '또한 영상 전체의 자막 유무와 이용 권한은 검사하지 않았어요.'),
         actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),
             child:const Text('링크 연결 안 함')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),
             child:const Text('같은 TikTok 영상으로 기록')),
         ]));
       if(tied!=true||!mounted){
         report('로컬 파일의 장면 일치만 확인했어요. TikTok 링크와는 연결하지 않았어요.');
         return;
       }
       setState((){
         state.matchedByUser[v.id]=origin.url;
         state.localSceneChecks[v.id]=
           '로컬 파일 장면 ${proof.matched}개 시간순 일치 · 해시 최저 거리 ${proof.best}/64';
         state.rejected[v.id]?.remove(origin.url);
         state.captioned[v.id]?.remove(origin.url);
       });
       await save();
       report('TikTok 후보를 같은 영상으로 기록했어요. 로컬 파일 장면 비교 통과 · '
         '기존 자막 및 원제작자/이용 권한은 계속 별도 확인해야 해요.');
     });
   }finally{
     activeStream=null;
     if(mounted)setState(()=>activeVideoId=null);
   }
 }
 Future<void> confirmOrigin(BenchVideo v,BenchOrigin origin)async{
   if(busy)return;
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
     title:const Text('자막 없는 원본을 확인했나요?'),
     content:Text('다음 사항을 영상 전체에서 직접 확인해 주세요.\n\n'
       '• 기준 영상과 실제 장면이 일치함\n'
       '• 이미 입혀진 제목이나 자막이 없음\n'
       '• 이용 권한을 확인함\n\n'
       '자동 검증 성공 건수로 집계하지 않습니다.\n\n${origin.url}'),
     actions:[
       TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
       FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('확인 후 저장'))
     ]));
   if(confirmed!=true||!mounted)return;
   setState((){
     state.confirmed[v.id]=origin.url;
     state.matchedByUser[v.id]=origin.url;
     state.chosen[v.id]=origin.url;
     state.rejected[v.id]?.remove(origin.url);
     state.captioned[v.id]?.remove(origin.url);
   });
   await save();
   report('직접 확인한 원본을 저장했어요. 검증 없이 자동 확정한 기록으로 계산하지 않아요.');
 }
 Widget candidateTile(BenchVideo v,BenchOrigin x){
   final colors=Theme.of(context).colorScheme;
   final autoVerified=x.source=='실제 동영상 교차확인';
   final manuallyVerified=x.source=='사용자 제공 원본';
   final verified=autoVerified||manuallyVerified;
   final captioned=x.source=='자막 검출 후보';
   final maybeCaptioned=x.source=='자막 확인 필요 후보';
   final selected=state.chosen[v.id]==x.url;
   final uri=Uri.tryParse(x.url);
   final host=uri?.host.toLowerCase()??'외부 링크';
   final provider=host.contains('instagram')?'Instagram':
     host.contains('tiktok')?'TikTok':
     host.contains('youtube')||host=='youtu.be'?'YouTube':'외부 링크';
   final status=verified?'원본 확인됨':captioned?'기존 자막 감지':
     maybeCaptioned?'자막 확인 필요':'영상 미검증';
   final statusColor=verified?colors.primary:
     captioned||maybeCaptioned?colors.error:colors.onSurfaceVariant;
   final statusIcon=verified?Icons.verified_outlined:
     captioned||maybeCaptioned?Icons.closed_caption_outlined:Icons.help_outline;
   return Card(
     margin:const EdgeInsets.only(bottom:10),
     elevation:0,
     color:selected?colors.primaryContainer.withValues(alpha:.45):colors.surfaceContainerLow,
     child:Padding(padding:const EdgeInsets.fromLTRB(14,12,14,10),
       child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Row(children:[
           Icon(statusIcon,size:20,color:statusColor),
           const SizedBox(width:8),
           Expanded(child:Text(provider,
             style:const TextStyle(fontWeight:FontWeight.w700,fontSize:14))),
           Text(status,style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:statusColor))
         ]),
         const SizedBox(height:6),
         Text(x.url,maxLines:1,overflow:TextOverflow.ellipsis,
           style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
         const SizedBox(height:6),
         Text(x.evidence,maxLines:3,overflow:TextOverflow.ellipsis,
           style:TextStyle(fontSize:12,height:1.4,color:colors.onSurfaceVariant)),
         const SizedBox(height:6),
         Wrap(spacing:4,runSpacing:2,crossAxisAlignment:WrapCrossAlignment.center,children:[
           TextButton.icon(
             onPressed:busy?null:()=>open(x.url),
             icon:const Icon(Icons.open_in_new,size:16),
             label:const Text('영상 보기')),
           if(verified)
             FilledButton.tonalIcon(
               onPressed:busy?null:()async{
                 setState(()=>state.chosen[v.id]=x.url);
                 await save();
               },
               icon:Icon(selected?Icons.check:Icons.movie_creation_outlined,size:16),
               label:Text(selected?'선택됨':'이 원본 사용')),
           if(!verified)
             TextButton.icon(onPressed:busy?null:()=>confirmOrigin(v,x),
               icon:const Icon(Icons.bookmark_add_outlined,size:16),
               label:const Text('직접 확인·저장')),
           if(!manuallyVerified)
             PopupMenuButton<String>(
               tooltip:'후보 관리',
               enabled:!busy,
               onSelected:(choice)=>rejectOrigin(v,x,captioned:choice=='caption'),
               itemBuilder:(ctx)=>const [
                 PopupMenuItem(value:'caption',child:Text('자막 있음 · 제외')),
                 PopupMenuItem(value:'different',child:Text('원본 아님 · 제외')),
               ],
               icon:const Icon(Icons.more_horiz)),
         ])
       ])));
 }
 Widget candidateCard(BenchVideo v){
   final userOriginal=state.confirmed[v.id];
   final rejected=state.rejected[v.id]??const <String>{};
   final captions=state.captioned[v.id]??const <String>{};
   final hidden=<String>{...rejected,...captions};
   final candidates=state.origins[v.id]??<BenchOrigin>[];
   final list=<BenchOrigin>[
     if(userOriginal!=null)BenchOrigin(userOriginal,
       '사용자가 직접 확인한 원본 · 검색 성공 통계에는 포함되지 않음','사용자 제공 원본'),
     ...candidates.where((x)=>x.url!=userOriginal&&!hidden.contains(x.url))
   ];
   int weight(BenchOrigin item){
     if(item.source=='사용자 제공 원본')return 0;
     if(item.source=='실제 동영상 교차확인')return 1;
     if(item.source=='자막 검출 후보'||item.source=='자막 확인 필요 후보')return 3;
     return 2;
   }
   list.sort((a,b)=>weight(a).compareTo(weight(b)));
   final selected=state.chosen[v.id];
   final all=shownAllCandidates.contains(v.id);
   final visible=all?list:list.take(3).toList();
   final verifiedCount=list.where((c)=>weight(c)<2).length;
   final theme=Theme.of(context);
   final colors=theme.colorScheme;
   return Card(
     elevation:0,
     margin:const EdgeInsets.only(bottom:16),
     shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20),
       side:BorderSide(color:colors.outlineVariant)),
     child:Padding(padding:const EdgeInsets.all(16),
       child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Row(children:[
           Expanded(child:Text(v.channel,
             style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:colors.primary))),
           Text('${v.duration}초 · 조회 ${v.views}',
             style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
         ]),
         const SizedBox(height:4),
         Text(v.title,maxLines:3,overflow:TextOverflow.ellipsis,
           style:theme.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
         Align(alignment:Alignment.centerLeft,child:TextButton.icon(
           onPressed:()=>open(v.url),
           icon:const Icon(Icons.play_circle_outline,size:18),
           label:const Text('벤치마킹 영상 보기'))),
         const SizedBox(height:6),
         if(activeVideoId==v.id&&busy)...[
           const LinearProgressIndicator(),
           const SizedBox(height:8),
           Text(message,style:TextStyle(fontSize:13,color:colors.primary)),
           Align(alignment:Alignment.centerRight,child:TextButton.icon(
             onPressed:cancelled?null:stopSearch,
             icon:const Icon(Icons.stop_circle_outlined,size:18),
             label:Text(cancelled?'중단 요청 중':'검색 중단'))),
         ]else...[
           SizedBox(width:double.infinity,child:FilledButton.icon(
             onPressed:busy?null:()=>search(v,continuous:true),
             icon:const Icon(Icons.manage_search),
             label:const Padding(padding:EdgeInsets.symmetric(vertical:5),
               child:Text('자막 없는 원본 찾기')))),
           const SizedBox(height:4),
           Text('일치 장면을 찾을 때까지 중복 없이 탐색 · 최대 6회',
             style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
         ],
         const SizedBox(height:10),
         if(framePreviews[v.id]?.isNotEmpty==true)...[
           Row(children:[
             const Icon(Icons.photo_library_outlined,size:17),
             const SizedBox(width:6),
             Text('검색 이미지 ${framePreviews[v.id]!.length}장',
               style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
             const Spacer(),
             Text('눌러서 이미지 검색',style:TextStyle(fontSize:11,color:colors.onSurfaceVariant))
           ]),
           const SizedBox(height:8),
           SizedBox(height:130,child:ListView.separated(
             scrollDirection:Axis.horizontal,
             itemCount:framePreviews[v.id]!.length,
             separatorBuilder:(_,i)=>const SizedBox(width:8),
             itemBuilder:(_,index)=>InkWell(
               borderRadius:BorderRadius.circular(12),
               onTap:()=>shareFrameToLens(v,index),
               child:ClipRRect(borderRadius:BorderRadius.circular(12),
                 child:Stack(children:[
                   Container(width:130,height:126,color:colors.surfaceContainer),
                   SizedBox(width:130,height:126,
                     child:Image.memory(framePreviews[v.id]![index],fit:BoxFit.contain)),
                   Positioned(right:5,bottom:5,child:CircleAvatar(
                     radius:13,backgroundColor:colors.surface,
                     child:Icon(Icons.image_search,size:17,color:colors.primary))),
                 ]))))),
           const SizedBox(height:10),
         ],
         Row(children:[
           const Icon(Icons.fact_check_outlined,size:18),
           const SizedBox(width:6),
           Expanded(child:Text('원본 후보 ${list.length}건',
             style:const TextStyle(fontWeight:FontWeight.w700))),
           Text(verifiedCount>0?'검증 또는 직접 확인 ${verifiedCount}건':'자동 확인 0건',
             style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
         ]),
         const SizedBox(height:8),
         if(list.isEmpty)
           Padding(padding:const EdgeInsets.symmetric(vertical:12),
             child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
               Icon(Icons.search_off,color:colors.onSurfaceVariant),
               const SizedBox(width:10),
               Expanded(child:Text('일치하는 원본 후보를 아직 못 찾았어요. '
                 '웹 이미지에 색인되지 않았을 수 있어요. 아래 다른 방법도 이용할 수 있어요.',
                 style:TextStyle(fontSize:13,color:colors.onSurfaceVariant))),
             ])),
         for(final x in visible)candidateTile(v,x),
         if(list.length>3)Align(alignment:Alignment.center,child:TextButton.icon(
           onPressed:()=>setState((){
             if(all){shownAllCandidates.remove(v.id);}else{shownAllCandidates.add(v.id);}
           }),
           icon:Icon(all?Icons.expand_less:Icons.expand_more),
           label:Text(all?'접기':'나머지 ${list.length-3}건 더 보기'))),
         if(selected!=null)...[
           const SizedBox(height:6),
           SizedBox(width:double.infinity,child:FilledButton.icon(
             onPressed:busy?null:()=>create(v),
             icon:const Icon(Icons.movie_creation_outlined),
             label:const Text('선택한 원본으로 영상 제작'))),
         ],
         ExpansionTile(
           key:PageStorageKey<String>('options_${v.id}'),
           tilePadding:EdgeInsets.zero,childrenPadding:EdgeInsets.zero,
           title:const Text('다른 방법 · 상세 내역',style:TextStyle(fontSize:13,fontWeight:FontWeight.w600)),
           leading:const Icon(Icons.tune,size:19),
           children:[
             Wrap(spacing:8,runSpacing:6,children:[
               OutlinedButton.icon(onPressed:busy?null:()=>search(v,manual:true),
                 icon:const Icon(Icons.video_file_outlined,size:17),
                 label:const Text('내 영상으로 검색')),
               OutlinedButton.icon(onPressed:busy?null:()=>addOrigin(v),
                 icon:const Icon(Icons.link,size:17),
                 label:const Text('후보 링크 추가')),
             ]),
             if(state.diagnostics[v.id]?.isNotEmpty==true)
               Padding(padding:const EdgeInsets.only(top:8),
                 child:SelectableText(state.diagnostics[v.id]!,
                   style:TextStyle(fontSize:12,height:1.4,color:colors.onSurfaceVariant))),
             if(rejected.isNotEmpty||captions.isNotEmpty)
               Wrap(spacing:8,children:[
                 if(rejected.isNotEmpty)TextButton(
                   onPressed:busy?null:()async{
                     setState(()=>state.rejected.remove(v.id));await save();
                   },child:Text('원본 아님 제외 ${rejected.length}건 초기화')),
                 if(captions.isNotEmpty)TextButton(
                   onPressed:busy?null:()async{
                     setState(()=>state.captioned.remove(v.id));await save();
                   },child:Text('자막 있음 제외 ${captions.length}건 초기화')),
               ]),
             const Padding(padding:EdgeInsets.symmetric(vertical:8),
               child:Text('이미지 검색 결과는 실제 동영상 검증과 다릅니다. '
                 '검증되지 않은 영상은 제작에 사용하기 전에 직접 확인해 주세요.',
                 style:TextStyle(fontSize:12))),
           ]),
       ])));
 }

 @override Widget build(BuildContext context){
   final selected=state.picked.where((v)=>v.eligibleForAutoSearch).toList();
   final count=state.top.values.fold<int>(0,(total,items)=>
     total+items.where((video)=>video.eligibleForAutoSearch).length);
   final unseen=<BenchVideo>[
     for(final channel in state.channels.keys)
       for(final video in state.top[channel]??<BenchVideo>[])
         if(video.eligibleForAutoSearch&&!state.seen.contains(video.id))video
   ];
   final colors=Theme.of(context).colorScheme;
   final theme=Theme.of(context);
   return Scaffold(
     appBar:AppBar(
       title:const Text('쇼츠 원본 찾기'),
       actions:[
         IconButton(icon:const Icon(Icons.help_outline),
           tooltip:'기능 안내',
           onPressed:()=>showModalBottomSheet<void>(
             context:context,showDragHandle:true,
             builder:(ctx)=>SafeArea(child:Padding(
               padding:const EdgeInsets.fromLTRB(20,8,20,24),
               child:Column(mainAxisSize:MainAxisSize.min,
                 crossAxisAlignment:CrossAxisAlignment.start,children:[
                 Text('어떻게 찾나요?',style:Theme.of(ctx).textTheme.titleLarge),
                 const SizedBox(height:12),
                 const Text('1. 채널을 갱신하고 새 소재를 고릅니다.\n'
                   '2. 주요 장면을 검색해 비슷한 게시물 후보를 모읍니다.\n'
                   '3. 가능한 후보의 실제 영상·길이·자막을 검사합니다.\n'
                   '4. 검증된 원본을 선택하거나 직접 확인해 제작합니다.\n\n'
                   '60초 이하 세로 영상만 자동 선정합니다. '
                   'Instagram은 영상 자동 검증이 지원되지 않아 링크를 직접 열어 확인해야 합니다.'),
                 const SizedBox(height:16),
                 Align(alignment:Alignment.centerRight,
                   child:FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('닫기'))),
               ])))),
         ),
       ]),
     body:loading?const Center(child:CircularProgressIndicator()):
       SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:850),
         child:ListView(padding:const EdgeInsets.fromLTRB(16,10,16,28),children:[
           Container(
             padding:const EdgeInsets.all(20),
             decoration:BoxDecoration(
               color:colors.primaryContainer.withValues(alpha:.40),
               borderRadius:BorderRadius.circular(22)),
             child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
               Row(children:[
                 Icon(Icons.smart_display_outlined,size:29,color:colors.primary),
                 const SizedBox(width:10),
                 Expanded(child:Text('원본 탐색',style:theme.textTheme.headlineSmall?.copyWith(
                   fontWeight:FontWeight.w800))),
               ]),
               const SizedBox(height:10),
               Text('소재를 고르고, 영상 장면과 자막까지 확인할 수 있어요.',
                 style:theme.textTheme.bodyMedium),
               const SizedBox(height:12),
               Wrap(spacing:8,runSpacing:6,children:[
                 Chip(avatar:const Icon(Icons.timer_outlined,size:16),
                   label:const Text('60초 이하')),
                 Chip(avatar:const Icon(Icons.crop_portrait,size:16),
                   label:const Text('세로형 우선')),
                 Chip(avatar:const Icon(Icons.subtitles_off_outlined,size:16),
                   label:const Text('기존 자막 검사')),
               ]),
             ])),
           const SizedBox(height:20),
           Row(children:[
             Expanded(child:Text('1. 소재 고르기',
               style:theme.textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800))),
             Text('숏폼 후보 $count개',style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
           ]),
           const SizedBox(height:9),
           Card(elevation:0,color:colors.surfaceContainerLow,
             child:Padding(padding:const EdgeInsets.all(14),child:Column(
               crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                 Text('등록 채널 ${state.channels.length}개 · 아직 보지 않은 소재 ${unseen.length}개',
                   style:TextStyle(fontSize:13,color:colors.onSurfaceVariant)),
                 const SizedBox(height:12),
                 FilledButton.icon(onPressed:busy||unseen.isEmpty?null:()=>drawRandom(),
                   icon:const Icon(Icons.casino_outlined),
                   label:const Padding(padding:EdgeInsets.symmetric(vertical:5),
                     child:Text('새 쇼츠 추천받기'))),
                 const SizedBox(height:8),
                 OutlinedButton.icon(onPressed:busy?null:scan,
                   icon:const Icon(Icons.refresh),
                   label:const Text('채널 영상 목록 갱신')),
                 if(unseen.isEmpty)Padding(
                   padding:const EdgeInsets.only(top:8),
                   child:Text(count==0?'먼저 채널의 영상을 갱신해 주세요.'
                     :'새 소재를 모두 살펴봤어요. 채널 영상 목록을 갱신해 주세요.',
                     style:TextStyle(fontSize:12,color:colors.onSurfaceVariant))),
               ]))),
           const SizedBox(height:18),
           Row(children:[
             Expanded(child:Text('2. 원본 찾기',
               style:theme.textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800))),
             if(selected.isNotEmpty)
               Text('${selected.length}개 선택됨',
                 style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
           ]),
           const SizedBox(height:8),
           if(selected.isEmpty)
             Card(elevation:0,color:colors.surfaceContainerLow,
               child:Padding(padding:const EdgeInsets.symmetric(vertical:25,horizontal:18),
                 child:Column(children:[
                   Icon(Icons.video_library_outlined,size:42,color:colors.outline),
                   const SizedBox(height:10),
                   Text('선정한 쇼츠가 없어요',style:theme.textTheme.titleMedium),
                   const SizedBox(height:4),
                   Text('위에서 새 쇼츠 추천받기를 누르면 이곳에 영상이 표시돼요.',
                     textAlign:TextAlign.center,
                     style:TextStyle(fontSize:13,color:colors.onSurfaceVariant))
                 ]))),
           for(final v in selected)candidateCard(v),
           if(busy&&activeVideoId==null)...[
             const SizedBox(height:8),
             const LinearProgressIndicator(),
           ],
           if(message.isNotEmpty)...[
             const SizedBox(height:10),
             Container(
               padding:const EdgeInsets.all(12),
               decoration:BoxDecoration(color:colors.surfaceContainerLow,
                 borderRadius:BorderRadius.circular(12)),
               child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                 Icon(Icons.info_outline,size:18,color:colors.primary),
                 const SizedBox(width:8),
                 Expanded(child:Text(message,maxLines:3,overflow:TextOverflow.ellipsis,
                   style:TextStyle(fontSize:12,color:colors.onSurfaceVariant))),
               ])),
           ],
           const SizedBox(height:14),
           ExpansionTile(
             key:const PageStorageKey<String>('studio_channels_settings'),
             tilePadding:const EdgeInsets.symmetric(horizontal:5),
             title:const Text('채널 관리'),
             subtitle:const Text('추가 · 제외 · 갱신 상태'),
             leading:const Icon(Icons.video_collection_outlined),
             children:[Padding(padding:const EdgeInsets.fromLTRB(8,0,8,12),
               child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                 Row(children:[
                   Expanded(child:TextField(controller:channelText,
                     enabled:!busy,
                     decoration:const InputDecoration(
                       labelText:'YouTube 채널 UC ID',
                       isDense:true,border:OutlineInputBorder()))),
                   const SizedBox(width:8),
                   IconButton.filledTonal(
                     onPressed:busy?null:(){
                       final id=channelText.text.trim();
                       if(!RegExp(r'^UC[\w-]{22}$').hasMatch(id)){
                         report('UC로 시작하는 유효한 YouTube 채널 ID를 입력해 주세요.');
                         return;
                       }
                       setState(()=>state.channels[id]=id);
                       channelText.clear();save();
                     },
                     tooltip:'채널 추가',
                     icon:const Icon(Icons.add))
                 ]),
                 const SizedBox(height:8),
                 for(final channel in state.channels.entries.toList())
                   ListTile(dense:true,contentPadding:EdgeInsets.zero,
                     title:Text(channel.value,maxLines:1,overflow:TextOverflow.ellipsis),
                     subtitle:Text('60초 이하 ${state.top[channel.key]?.where((v)=>v.eligibleForAutoSearch).length??0}개'),
                     trailing:IconButton(
                       onPressed:busy?null:()=>removeChannel(channel.key,channel.value),
                       tooltip:'채널 제외 (확인)',
                       icon:const Icon(Icons.remove_circle_outline))),
               ]))],
           ),
           ExpansionTile(
             key:const PageStorageKey<String>('studio_api_settings'),
             initiallyExpanded:keyText.text.trim().isEmpty,
             tilePadding:const EdgeInsets.symmetric(horizontal:5),
             title:const Text('API 키 및 검색 기록'),
             subtitle:const Text('연결 · 백업 · 복원'),
             leading:const Icon(Icons.settings_outlined),
             children:[Padding(padding:const EdgeInsets.fromLTRB(8,2,8,14),
               child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                 TextField(controller:keyText,enabled:!busy,obscureText:true,
                   enableSuggestions:false,autocorrect:false,
                   decoration:const InputDecoration(
                     labelText:'YouTube Data API 키',isDense:true,border:OutlineInputBorder())),
                 const SizedBox(height:7),
                 Align(alignment:Alignment.centerRight,child:TextButton(
                   onPressed:busy?null:()=>run(()async{
                     await Native.call('saveBenchmarkApiKey',{'key':keyText.text.trim()});
                     report('YouTube API 키를 안전하게 저장했어요.');
                   }),child:const Text('YouTube 키 저장'))),
                 const SizedBox(height:8),
                 TextField(controller:visionKeyText,enabled:!busy,obscureText:true,
                   enableSuggestions:false,autocorrect:false,
                   decoration:const InputDecoration(
                     labelText:'Cloud Vision API 키 (선택)',
                     helperText:'비워두면 YouTube API 키를 이용합니다.',
                     isDense:true,border:OutlineInputBorder())),
                 const SizedBox(height:7),
                 Align(alignment:Alignment.centerRight,child:TextButton(
                   onPressed:busy?null:()=>run(()async{
                     await Native.call('saveBenchmarkVisionKey',{'key':visionKeyText.text.trim()});
                     report('Cloud Vision 키를 안전하게 저장했어요.');
                   }),child:const Text('Vision 키 저장'))),
                 const Divider(height:25),
                 Text('실수로 삭제해도 검색 기록을 다시 가져올 수 있도록 '
                   '백업을 메모 등에 보관할 수 있어요.',
                   style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
                 const SizedBox(height:9),
                 Wrap(spacing:8,runSpacing:8,children:[
                   OutlinedButton.icon(onPressed:busy?null:exportBackup,
                     icon:const Icon(Icons.copy_all_outlined,size:17),
                     label:const Text('기록 백업 복사')),
                   OutlinedButton.icon(onPressed:busy?null:restoreBackup,
                     icon:const Icon(Icons.settings_backup_restore,size:17),
                     label:const Text('백업 기록 복원')),
                 ]),
                 Text('API 키와 영상 파일은 백업에서 제외됩니다.',
                   style:TextStyle(fontSize:11,color:colors.onSurfaceVariant))
               ]))],
           ),
           const SizedBox(height:12),
         ]))))
   );
 }
}
