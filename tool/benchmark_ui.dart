import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'benchmark_stream.dart';
import 'benchmark_oneclick.dart';
import 'benchmark_duration.dart';
import 'package:flutter/material.dart';
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
 bool busy=false,loading=true;
 String? activeVideoId;
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
 Widget candidateCard(BenchVideo v){
   final userOriginal=state.confirmed[v.id];
   final dismissed=state.rejected[v.id]??const <String>{};
   final captioned=state.captioned[v.id]??const <String>{};
   final hidden=<String>{...dismissed,...captioned};
   final other=state.origins[v.id]??<BenchOrigin>[];
   final list=<BenchOrigin>[
     if(userOriginal!=null)BenchOrigin(userOriginal,
       '사용자가 원본이라고 제공한 링크 · 자동 이미지 검색의 발견 성과로 계산하지 않음',
       '사용자 제공 원본'),
     ...other.where((x)=>x.url!=userOriginal&&!hidden.contains(x.url))
   ];
   final selected=state.chosen[v.id];
   final canCreate=selected!=null&&!busy;
  return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Text(v.channel,style:const TextStyle(fontSize:12)),
     Text(v.title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
     Text('조회 ${v.views} · ${v.duration}초 · ${v.publishedAt}',style:const TextStyle(fontSize:12)),
     TextButton.icon(onPressed:()=>open(v.url),icon:const Icon(Icons.open_in_new),
      label:const Text('벤치마킹 영상 확인')),
     Wrap(spacing:8,children:[
      FilledButton.icon(onPressed:busy?null:()=>search(v),
        icon:const Icon(Icons.auto_awesome),label:const Text('원클릭 원본 탐색 → 검증 → 제작')),
      FilledButton.icon(onPressed:busy?null:()=>search(v,continuous:true),
        icon:const Icon(Icons.repeat),label:const Text('연속찾기 · 일치할 때까지 탐색')),
      OutlinedButton(onPressed:busy?null:()=>search(v,manual:true),child:const Text('영상 파일 직접 선택')),
      OutlinedButton(onPressed:busy?null:()=>addOrigin(v),child:const Text('원본 링크 추가'))]),
     if(busy&&activeVideoId==v.id)...[
       const SizedBox(height:8),
       const LinearProgressIndicator(),
       const SizedBox(height:4),
       SelectableText(message,style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold)),
       Align(alignment:Alignment.centerLeft,child:TextButton.icon(
         onPressed:cancelled?null:stopSearch,
         icon:const Icon(Icons.stop_circle_outlined),
         label:Text(cancelled?'중단 처리 중':'검색 중단'))),
     ],
     if(framePreviews[v.id]?.isNotEmpty==true)...[
       const Text('자막 재검증을 통과한 검색용 장면 · 사진을 누르면 같은 크롭을 이미지 검색 앱으로 공유',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
       const SizedBox(height:6),
       SizedBox(height:124,child:ListView.separated(
         scrollDirection:Axis.horizontal,
         itemCount:framePreviews[v.id]!.length,
         separatorBuilder:(_,i)=>const SizedBox(width:6),
         itemBuilder:(_,index)=>InkWell(
           onTap:()=>shareFrameToLens(v,index),
           child:Stack(children:[
             Image.memory(framePreviews[v.id]![index],
               width:105,height:120,fit:BoxFit.cover),
             const Positioned(right:4,bottom:4,
               child:Icon(Icons.image_search,color:Colors.white,size:24)),
           ])))),
       const SizedBox(height:4),
       const Text('프레임을 터치하면 화면에 표시된 OCR 검증 크롭 그대로 Google Lens 등에 공유해요. 원본 전체 화면이나 추가 자막은 다시 붙이지 않아요. OCR 누락은 여전히 가능해요.',
          style:TextStyle(fontSize:12)),
       const SizedBox(height:8),
     ],
     if(!busy&&state.diagnostics[v.id]?.isNotEmpty==true)
       Padding(padding:const EdgeInsets.symmetric(vertical:8),
         child:SelectableText('마지막 원본 탐색 진단: ${state.diagnostics[v.id]}',
            style:const TextStyle(fontSize:12))),
     if(captioned.isNotEmpty)Align(alignment:Alignment.centerLeft,
       child:TextButton.icon(
         onPressed:busy?null:()async{
           setState(()=>state.captioned.remove(v.id));
           await save();
           report('자막이 있는 것으로 제외했던 ${captioned.length}건의 링크를 다시 검색할 수 있어요.');
         },
         icon:const Icon(Icons.undo,size:16),
         label:Text('자막 있음으로 제외한 ${captioned.length}건 초기화'))),
     if(dismissed.isNotEmpty)Align(alignment:Alignment.centerLeft,
       child:TextButton.icon(
         onPressed:busy?null:()async{
           setState(()=>state.rejected.remove(v.id));
           await save();
           report('이 영상에서 제외했던 후보 ${dismissed.length}건을 다시 표시할 수 있어요.');
         },
         icon:const Icon(Icons.undo,size:16),
         label:Text('원본 아님으로 제외한 ${dismissed.length}건 초기화'))),
     if(list.isEmpty&&!busy)const Text('원본 후보 없음 · 위 진단을 확인하세요. 웹 이미지 색인에 영상 원본이 없을 수도 있습니다.',
       style:TextStyle(fontSize:12)),
     for(final x in list)Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       RadioListTile<String>(dense:true,contentPadding:EdgeInsets.zero,
      title:Text('${x.source}: ${x.url}',maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text(x.evidence,style:const TextStyle(fontSize:12)),
      value:x.url,groupValue:selected,
      onChanged:busy||x.source=='실제 영상 미검증 후보'||
          x.source=='자막 검출 후보'||
          x.source=='자막 확인 필요 후보'||
          x.source=='연관 페이지만 확인'?null:(u){
        setState(()=>state.chosen[v.id]=u!);save();}),
     Padding(padding:const EdgeInsets.only(left:32,bottom:8),
       child:Align(alignment:Alignment.centerLeft,
         child:TextButton.icon(onPressed:()=>open(x.url),
           icon:const Icon(Icons.open_in_new,size:17),
           label:const Text('후보 게시물 열어보기')))),
       if(x.source!='사용자 제공 원본')
         Wrap(spacing:6,children:[
           TextButton.icon(onPressed:busy?null:()async{
             setState((){
               state.rejected.putIfAbsent(v.id,()=> <String>{}).add(x.url);
               state.origins[v.id]?.removeWhere((o)=>o.url==x.url);
               if(state.chosen[v.id]==x.url)state.chosen.remove(v.id);
             });
             await save();
             report('원본 아님으로 제외했어요. 다음 검색에서 이 링크는 건너뜁니다.');
           },icon:const Icon(Icons.block,size:16),
             label:const Text('원본 아님')),
           TextButton.icon(onPressed:busy?null:()async{
             setState((){
               state.captioned.putIfAbsent(v.id,()=> <String>{}).add(x.url);
               state.origins[v.id]?.removeWhere((o)=>o.url==x.url);
               if(state.chosen[v.id]==x.url)state.chosen.remove(v.id);
               if(state.confirmed[v.id]==x.url)state.confirmed.remove(v.id);
             });
             await save();
             report('기존 자막이 포함된 후보로 제외했어요. 이후 검색에서는 이 링크를 건너뛰어요.');
           },icon:const Icon(Icons.closed_caption_disabled,size:16),
             label:const Text('자막 있음 · 제외')),
           TextButton.icon(onPressed:busy?null:()async{
             final confirmed=await showDialog<bool>(context:context,
               builder:(ctx)=>AlertDialog(
                 title:const Text('자막 없는 실제 원본을 확인했나요?'),
                 content:Text('검색 결과가 유사하다는 것만으로는 확인할 수 없어요. '
                     '영상 전체의 장면이 일치하고, 이미 입혀진 제목·단어 자막이 없으며 '
                     '사용 권한도 직접 확인했을 때만 저장하세요. '
                     '이 확인은 자동 검증 성공으로 집계하지 않습니다.\\n\\n${x.url}'),
                 actions:[
                   TextButton(onPressed:()=>Navigator.pop(ctx,false),
                     child:const Text('취소')),
                   FilledButton(onPressed:()=>Navigator.pop(ctx,true),
                     child:const Text('확인 후 저장')),
                 ]));
             if(confirmed!=true||!mounted)return;
             setState((){
               state.confirmed[v.id]=x.url;
               state.chosen[v.id]=x.url;
               state.rejected[v.id]?.remove(x.url);
               state.captioned[v.id]?.remove(x.url);
             });
             await save();
             report('사용자가 확인한 원본으로 보존했어요. 다음 검색으로 삭제되지 않아요.');
           },icon:const Icon(Icons.bookmark_add_outlined,size:16),
             label:const Text('원본 확인·저장')),
         ]), ]),
     if(selected!=null)TextButton.icon(onPressed:()=>open(selected),
      icon:const Icon(Icons.open_in_new),label:const Text('선택한 원본 확인')),
     const SizedBox(height:8),
     FilledButton.icon(onPressed:canCreate?()=>create(v):null,
      icon:const Icon(Icons.movie_creation_outlined),
      label:const Text('선택한 원본 → 템플릿 제작')),
    ])));
 }
 @override Widget build(BuildContext context){
  final selected=state.picked.where((v)=>v.eligibleForAutoSearch).toList();
  final count=state.top.values.fold<int>(0,(a,v)=>
    a+v.where((item)=>item.eligibleForAutoSearch).length);
  return Scaffold(appBar:AppBar(title:const Text('벤치마킹 쇼츠 탐색')),
   body:loading?const Center(child:CircularProgressIndicator()):
   ListView(padding:const EdgeInsets.all(16),children:[
    const Text('60초 이하 숏폼 후보만 선정 · 세로형 스트림 확인 · 자막 없는 원본 이미지 검색',style:TextStyle(fontSize:14)),
    const SizedBox(height:12),
    TextField(controller:keyText,obscureText:true,enableSuggestions:false,autocorrect:false,
      decoration:const InputDecoration(labelText:'YouTube Data API v3 키 (암호화 저장)')),
    TextButton(onPressed:busy?null:()=>run(()async{
       await Native.call('saveBenchmarkApiKey',{'key':keyText.text.trim()});
       report('YouTube Data API 키 저장 완료');
           }),child:const Text('API 키 저장')),
    const SizedBox(height:8),
    TextField(controller:visionKeyText,obscureText:true,enableSuggestions:false,autocorrect:false,
      decoration:const InputDecoration(labelText:'Cloud Vision Web Detection API 키',
        helperText:'Cloud Vision API 활성화 필요 · 빈칸이면 YouTube API 키 사용')),
    TextButton(onPressed:busy?null:()=>run(()async{
       await Native.call('saveBenchmarkVisionKey',{'key':visionKeyText.text.trim()});
       report('Vision 검색 키를 암호화 저장했어요.');
     }),child:const Text('Vision API 키 저장')),
    const Text('역이미지 검색으로 찾은 Instagram 등은 실제 영상/자막 자동 검증이 아니라 후보 링크입니다. YouTube·TikTok 영상은 접근 가능한 경우에만 장면과 자막을 검사하며, 자막 의심 후보는 자동 제작에서 제외합니다.',
      style:TextStyle(fontSize:12)),
    Text('채널 ${state.channels.length}개 · 순위 후보 $count개',style:const TextStyle(fontWeight:FontWeight.bold)),
    Row(children:[
     Expanded(child:TextField(controller:channelText,decoration:const InputDecoration(labelText:'채널 UC ID 추가'))),
     IconButton(icon:const Icon(Icons.add),onPressed:busy?null:(){
       final id=channelText.text.trim();
       if(!RegExp(r'^UC[\w-]{22}$').hasMatch(id)){report('유효한 UC 채널 ID를 입력하세요.');return;}
       setState(()=>state.channels[id]=id);channelText.clear();save();
     })]),
    for(final c in state.channels.entries.toList())ListTile(dense:true,contentPadding:EdgeInsets.zero,
      title:Text(c.value),
      subtitle:Text('60초 이하 ${state.top[c.key]?.where((v)=>v.eligibleForAutoSearch).length??0}개 · 총 ${state.scanned[c.key]??0}개 분석'
       '${state.complete[c.key]==false?" · 불완전 수집":""}'),
      trailing:IconButton(icon:const Icon(Icons.close),tooltip:'채널 제외',
        onPressed:busy?null:(){setState(()=>state.channels.remove(c.key));save();})),
    FilledButton.icon(onPressed:busy?null:scan,icon:const Icon(Icons.refresh),
      label:const Text('60초 이하 영상만 상위 50개 갱신')),
    FilledButton.icon(
      onPressed:busy||count==0?null:()async{
        final pool=<BenchVideo>[];
        for(final key in state.channels.keys){
          for(final video in state.top[key]??<BenchVideo>[]){
            if(video.eligibleForAutoSearch&&!state.seen.contains(video.id))pool.add(video);
          }
        }
        if(pool.isEmpty){report('추첨할 새 영상이 없어요. 갱신 후 기존 추첨을 확인하세요.');return;}
        final video=pool[Random.secure().nextInt(pool.length)];
        state.selected..clear()..add(video.id);
        state.seen.add(video.id);
        await save();
        if(mounted)setState((){});
        await search(video);
      },
      icon:const Icon(Icons.auto_awesome),
      label:const Text('전체 원클릭 · 랜덤 1개 → 원본 검증 → 템플릿')),
    OutlinedButton.icon(onPressed:busy||count==0?null:()=>run(()async{
       state.draw();report('${state.selected.length}개 랜덤 추첨 · 이미 추첨한 영상은 제외');}),
      icon:const Icon(Icons.shuffle),label:const Text('채널마다 무작위 1개 추첨')),
    if(busy)const LinearProgressIndicator(),
    if(message.isNotEmpty)SelectableText(message,style:const TextStyle(fontSize:12)),
    const Divider(height:32),
    Text('이번 선정 ${selected.length}개',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
         const Text('이미지 한 장에서 발견된 링크도 탐색하되 실제 동영상과 프레임을 대조해요. 검색 중에는 해당 카드에 진행 상황과 중단 버튼이 표시됩니다.',
     style:TextStyle(fontSize:12)),
    for(final v in selected)candidateCard(v),
   ]));
 }
}
