import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'benchmark_stream.dart';
import 'benchmark_oneclick.dart';
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
 final fullFramePreviews=<String,List<Uint8List>>{};
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
       c.source=='실제 동영상 교차확인'||c.source=='검증되지 않은 검색 후보'||c.source=='직접 추가').toList();
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
 Future<void> search(BenchVideo v,{bool manual=false})async{
  if(busy)return;
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
    final previews=<Uint8List>[],uncropped=<Uint8List>[];
    for(final frame in frames){
      if(frame is Map&&frame['content'] is String){
        previews.add(base64Decode(frame['content'] as String));
        final uncroppedBytes=frame['originalContent'];
        uncropped.add(uncroppedBytes is String?
          base64Decode(uncroppedBytes):base64Decode(frame['content'] as String));
      }
    }
    if(mounted)setState((){
      framePreviews[v.id]=previews;
      fullFramePreviews[v.id]=uncropped;
    });
    report('한국어 OCR로 글자 영역을 제외한 검색 장면 ${previews.length}장 확보 · 동일/유사 길이 (±20%, 최소 ±3초) 후보만 자동 확인');
    final key=visionKeyText.text.trim().isNotEmpty?visionKeyText.text.trim():keyText.text.trim();
    final explorer=OneClickExplorer(key,(message)=>report(message),
      youtubeApiKey:keyText.text.trim(),benchmarkSeconds:v.duration);
    activeExplorer=explorer;
    final result=await explorer.run(v.id,frames);
    state.diagnostics[v.id]=result.diagnostic;
    if(cancelled)throw const OneClickCancelled();
    final visible=<BenchOrigin>[];
    for(final item in result.results){
      final prefix=switch(item.status){
        'checked'=>'검증됨 · 자막 의심 미검출',
        'overlay'=>'제외 · 기존 자막 의심',
        'unrelated'=>'제외 · 실제 영상 불일치',
        'duration'=>'제외 · 영상 길이 불일치 또는 확인 불가',
        'unsupported'=>'확인 필요 · 플랫폼 미지원',
        'error'=>'확인 실패',_=>'확인 필요'
      };
      visible.add(BenchOrigin(item.origin.url,'$prefix · ${item.detail}',item.status=='checked'?
        '실제 동영상 교차확인':'검증되지 않은 검색 후보'));
    }
    state.origins[v.id]=visible;
    state.chosen.remove(v.id);
    await save();
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
    }else{
      report('${result.diagnostic} 최종 템플릿 제작 가능 원본 없음. 후보별 사유를 아래에서 확인하세요.');
    }
  });
  }finally{
    activeExplorer=null;
    activeStream=null;
    if(mounted)setState(()=>activeVideoId=null);
  }
 }
 Future<void> shareFrameToLens(BenchVideo v,int index)async{
   final originals=fullFramePreviews[v.id];
   final crops=framePreviews[v.id];
   final frames=(originals!=null&&index<originals.length)?originals:crops;
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
   final list=state.origins[v.id]??[],selected=state.chosen[v.id];
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
       const Text('OCR로 자막 위치를 피해서 추출한 장면 · 사진을 누르면 전체 프레임을 이미지 검색 앱으로 공유',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
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
       const Text('프레임을 터치해 Google Lens 등으로 검색하세요. 검색 앱에서 인물·물체만 선택하면 추가 자막을 피할 수 있어요. 검색 결과 확인은 수동입니다.',
          style:TextStyle(fontSize:12)),
       const SizedBox(height:8),
     ],
     if(!busy&&state.diagnostics[v.id]?.isNotEmpty==true)
       Padding(padding:const EdgeInsets.symmetric(vertical:8),
         child:SelectableText('마지막 원본 탐색 진단: ${state.diagnostics[v.id]}',
            style:const TextStyle(fontSize:12))),
     if(list.isEmpty&&!busy)const Text('원본 후보 없음 · 위 진단을 확인하세요. 웹 이미지 색인에 영상 원본이 없을 수도 있습니다.',
       style:TextStyle(fontSize:12)),
     for(final x in list)Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       RadioListTile<String>(dense:true,contentPadding:EdgeInsets.zero,
      title:Text('${x.source}: ${x.url}',maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text(x.evidence,style:const TextStyle(fontSize:12)),
      value:x.url,groupValue:selected,
      onChanged:busy||x.source=='검증되지 않은 검색 후보'?null:(u){setState(()=>state.chosen[v.id]=u!);save();}),
     Padding(padding:const EdgeInsets.only(left:32,bottom:8),
       child:Align(alignment:Alignment.centerLeft,
         child:TextButton.icon(onPressed:()=>open(x.url),
           icon:const Icon(Icons.open_in_new,size:17),
           label:const Text('후보 게시물 열어보기')))), ]),
     if(selected!=null)TextButton.icon(onPressed:()=>open(selected),
      icon:const Icon(Icons.open_in_new),label:const Text('선택한 원본 확인')),
     const SizedBox(height:8),
     FilledButton.icon(onPressed:canCreate?()=>create(v):null,
      icon:const Icon(Icons.movie_creation_outlined),
      label:const Text('선택한 원본 → 템플릿 제작')),
    ])));
 }
 @override Widget build(BuildContext context){
  final selected=state.picked;
  final count=state.top.values.fold<int>(0,(a,v)=>a+v.length);
  return Scaffold(appBar:AppBar(title:const Text('벤치마킹 쇼츠 탐색')),
   body:loading?const Center(child:CircularProgressIndicator()):
   ListView(padding:const EdgeInsets.all(16),children:[
    const Text('채널별 상위 50개 → 랜덤 선정 → 주요 장면 역이미지 검색 → 기존 템플릿',style:TextStyle(fontSize:14)),
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
    const Text('원클릭으로 영상 스트림 → 6개 프레임 → 역이미지 후보 → 최대 5개 실제 동영상 비교·자막 검사 → 확인된 TikTok 원본은 기존 편집기로 연결합니다. Instagram 및 자동 검증 실패는 수동 확인이 필요해요.',
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
      subtitle:Text('상위 ${state.top[c.key]?.length??0}개 · 총 ${state.scanned[c.key]??0}개 분석'
       '${state.complete[c.key]==false?" · 불완전 수집":""}'),
      trailing:IconButton(icon:const Icon(Icons.close),tooltip:'채널 제외',
        onPressed:busy?null:(){setState(()=>state.channels.remove(c.key));save();})),
    FilledButton.icon(onPressed:busy?null:scan,icon:const Icon(Icons.refresh),
      label:const Text('채널별 조회수 상위 50개 갱신')),
    FilledButton.icon(
      onPressed:busy||count==0?null:()async{
        final pool=<BenchVideo>[];
        for(final key in state.channels.keys){
          for(final video in state.top[key]??<BenchVideo>[]){
            if(!state.seen.contains(video.id))pool.add(video);
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
