import 'dart:convert';
import 'dart:io';
import 'benchmark_stream.dart';
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
       c.source=='프레임 역이미지 검색'||c.source=='직접 추가').toList();
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
    report('Cloud Vision API 키를 입력해 주세요.');
    return;
  }
  await run(()async{
    List<dynamic>? frames;
    if(manual){
      report('기기에서 영상 파일을 선택해 주세요.');
      frames=await Native.call<List<dynamic>>('benchmarkPickFrames');
      if(frames==null){report('파일 선택을 취소했어요.');return;}
    }else{
      final path=await Native.call<String>('benchmarkStreamCachePath',{'id':v.id});
      if(path==null)throw StateError('기기의 영상 임시 경로를 확인할 수 없어요.');
      try{
        final resolver=BenchmarkStreamResolver();
        await resolver.download(v.id,path,(msg)=>report(msg));
        report('실제 YouTube 스트림에서 프레임 추출 중');
        frames=await Native.call<List<dynamic>>('benchmarkExtractFramesFromCache',{'id':v.id});
      }finally{
        try{
          final tmp=File(path);
          if(await tmp.exists())await tmp.delete();
        }catch(_){}
      }
    }
    if(frames==null||frames.isEmpty){
      report('검색 가능한 영상 장면이 없어요. 직접 파일 선택으로 재시도해 주세요.');
      return;
    }
    report('실제 프레임 ${frames.length}장으로 역이미지 검색 중');
    final key=visionKeyText.text.trim().isNotEmpty?visionKeyText.text.trim():keyText.text.trim();
    final engine=FrameReverseSearch(key);
    try{
      final results=await engine.find(v.id,frames);
      state.origins[v.id]=results;
      state.chosen.remove(v.id);
      report(results.isEmpty?'일치하는 게시물 URL을 찾지 못했어요. 영상 파일 선택 방식으로 재검색할 수 있어요.':
        '프레임이 반복 일치하는 원본 후보 ${results.length}개를 찾았어요.');
    }finally{engine.close();}
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
      OutlinedButton(onPressed:busy?null:()=>search(v),child:const Text('영상 스트림 자동 검색')),
      OutlinedButton(onPressed:busy?null:()=>search(v,manual:true),child:const Text('영상 파일 직접 선택')),
      OutlinedButton(onPressed:busy?null:()=>addOrigin(v),child:const Text('원본 링크 추가'))]),
     if(list.isEmpty)const Text('주요 장면 이미지 검색 결과 없음',style:TextStyle(fontSize:12)),
     for(final x in list)RadioListTile<String>(dense:true,contentPadding:EdgeInsets.zero,
      title:Text('${x.source}: ${x.url}',maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text(x.evidence,style:const TextStyle(fontSize:12)),
      value:x.url,groupValue:selected,
      onChanged:busy?null:(u){setState(()=>state.chosen[v.id]=u!);save();}),
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
    const Text('선정 영상의 공개 스트림에서 주요 장면을 자동 추출합니다. 스트림을 열 수 없는 경우 직접 파일 선택을 이용하세요. 제목·설명란·Tavily는 검색하지 않아요.',
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
         const Text('여러 이미지에서 일치한 페이지를 우선 표시해요. 후보가 최초 제작자라고 확정되는 것은 아니에요.',
     style:TextStyle(fontSize:12)),
    for(final v in selected)candidateCard(v),
   ]));
 }
}
