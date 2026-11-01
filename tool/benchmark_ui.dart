import 'dart:convert';
import 'dart:io';
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
 bool busy=false,loading=true;
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
 void report(String s){if(mounted)setState(()=>message=s);}
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
        await BenchmarkStreamResolver().download(v.id,path,(message)=>report(message));
        frames=await Native.call<List<dynamic>>('benchmarkExtractFramesFromCache',{'id':v.id});
      }finally{
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
    if(mounted)setState(()=>framePreviews[v.id]=previews);
    final key=visionKeyText.text.trim().isNotEmpty?visionKeyText.text.trim():keyText.text.trim();
    final explorer=OneClickExplorer(key,(message)=>report(message));
    final result=await explorer.run(v.id,frames);
    final visible=<BenchOrigin>[];
    for(final item in result.results){
      final prefix=switch(item.status){
        'checked'=>'검증됨 · 자막 의심 미검출',
        'overlay'=>'제외 · 기존 자막 의심',
        'unrelated'=>'제외 · 실제 영상 불일치',
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
      report('원클릭 탐색 완료 · 이미지 후보 ${result.total}개 · 실제 영상 검사 ${result.inspected}개 · 자동 제작 조건을 통과한 TikTok 원본 없음. 화면의 후보와 사유를 확인해 주세요.');
    }
  });
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
     if(framePreviews[v.id]?.isNotEmpty==true)...[
       const Text('실제 검색에 사용한 장면 (자막 영역 크롭)',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
       const SizedBox(height:6),
       SizedBox(height:124,child:ListView.separated(
         scrollDirection:Axis.horizontal,
         itemCount:framePreviews[v.id]!.length,
         separatorBuilder:(_,i)=>const SizedBox(width:6),
         itemBuilder:(_,index)=>Image.memory(framePreviews[v.id]![index],
           width:105,height:120,fit:BoxFit.cover))),
       const SizedBox(height:8),
     ],
     if(list.isEmpty)const Text('확인된 직접 일치 후보 없음 · 관련 영상만 나온 경우 표시하지 않아요.',
       style:TextStyle(fontSize:12)),
     for(final x in list)RadioListTile<String>(dense:true,contentPadding:EdgeInsets.zero,
      title:Text('${x.source}: ${x.url}',maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text(x.evidence,style:const TextStyle(fontSize:12)),
      value:x.url,groupValue:selected,
      onChanged:busy||x.source=='검증되지 않은 검색 후보'?null:(u){setState(()=>state.chosen[v.id]=u!);save();}),
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
    OutlinedButton.icon(onPressed:busy||count==0?null:()=>run(()async{
       state.draw();report('${state.selected.length}개 랜덤 추첨 · 이미 추첨한 영상은 제외');}),
      icon:const Icon(Icons.shuffle),label:const Text('채널마다 무작위 1개 추첨')),
    if(busy)const LinearProgressIndicator(),
    if(message.isNotEmpty)SelectableText(message,style:const TextStyle(fontSize:12)),
    const Divider(height:32),
    Text('이번 선정 ${selected.length}개',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
         const Text('완전·부분 이미지 매칭을 구분하고, 서로 다른 3개 이상 장면에서 직접 일치할 때만 후보를 표시합니다. 최초 제작자임을 보장하지는 않아요.',
     style:TextStyle(fontSize:12)),
    for(final v in selected)candidateCard(v),
   ]));
 }
}
