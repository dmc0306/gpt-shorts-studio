import 'dart:io';
import 'dart:async';
import 'benchmark_data.dart';
import 'benchmark_stream.dart';
import 'bridge.dart';
import 'model.dart';
import 'tiktok_download.dart';
import 'vision_reverse.dart';

class OneClickCancelled implements Exception {
  const OneClickCancelled();
  @override String toString()=> '원본 탐색을 중단했어요.';
}

class CandidateCheck {
  const CandidateCheck(this.origin,this.status,this.detail,{this.clip});
  final BenchOrigin origin;
  final String status; // checked, overlay, unrelated, unsupported, error
  final String detail;
  final Clip? clip;
}

class OneClickResult {
  const OneClickResult(this.results,{required this.total,required this.inspected});
  final List<CandidateCheck> results;
  final int total,inspected;
  CandidateCheck? get best {
    for(final r in results){if(r.status=='checked'&&r.clip!=null)return r;}
    return null;
  }
}

/// Each reference frame may correlate with a different original clip in a
/// compilation. Two *distinct* scenes with low dHash distance are required.
class VideoMatch {
  static int distance(String a,String b){
    if(!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(a)||!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(b))return 64;
    var diff=BigInt.parse(a,radix:16)^BigInt.parse(b,radix:16);
    var bits=0;
    while(diff>BigInt.zero){diff=diff&(diff-BigInt.one);bits++;}
    return bits;
  }
  static ({int matched,int best,int distinctCandidate}) match(List<dynamic> reference,List<dynamic> candidate){
    final candidates=<({String hash,double contrast,int index})>[];
    for(var i=0;i<candidate.length;i++){
      final value=candidate[i];
      if(value is! Map)continue;
      final hash=value['hash'] as String? ?? '';
      final contrast=(value['contrast'] as num? ?? 0).toDouble();
      if(hash.length==16&&contrast>=15)candidates.add((hash:hash,contrast:contrast,index:i));
    }
    final observed=<int>{},matchedReference=<int>{};
    var best=64;
    for(var i=0;i<reference.length;i++){
      final item=reference[i];
      if(item is! Map)continue;
      final hash=item['hash'] as String? ?? '';
      final contrast=(item['contrast'] as num? ?? 0).toDouble();
      if(hash.length!=16||contrast<15)continue;
      var minDistance=64,closest=-1;
      for(final sample in candidates){
        final d=distance(hash,sample.hash);
        if(d<minDistance){minDistance=d;closest=sample.index;}
      }
      if(minDistance<best)best=minDistance;
      if(minDistance<=9&&closest>=0){
        matchedReference.add(i);observed.add(closest);
      }
    }
    return(matched:matchedReference.length,best:best,distinctCandidate:observed.length);
  }
  static bool strong(({int matched,int best,int distinctCandidate}) m)=>
    m.matched>=2&&m.distinctCandidate>=2&&m.best<=6;
}

/// ML Kit OCR bounding boxes only; repeated top/bottom text across sampled
/// times is treated conservatively as a possible creator-added overlay.
class OverlayCheck {
  static bool suspicious(Map<dynamic,dynamic> ocr){
    final lines=ocr['lines'];
    if(lines is! List)return true; // Scanner failure must not pass as clean.
    final cells=<int,Set<int>>{};
    for(final raw in lines){
      if(raw is! Map)continue;
      if(raw['watermark']==true)continue;
      final y=(raw['y'] as num? ?? 0).toDouble(),x=(raw['x'] as num? ?? 0).toDouble();
      final width=(raw['w'] as num? ?? 0).toDouble();
      final letters=(raw['letters'] as num? ?? 0).toInt();
      final time=(raw['time'] as num? ?? -1).toDouble();
      if(letters<3||width<.18||time<0)continue;
      if(!(y<.24||y>.66))continue;
      final key=((y*12).round()*20)+(x*4).round();
      cells.putIfAbsent(key,()=>{}).add(time.floor());
    }
    return cells.values.any((times)=>times.length>=3);
  }
}

class OneClickExplorer {
  OneClickExplorer(this.apiKey,this.report);
  final String apiKey;
  final void Function(String message) report;
  static const maxVerifications=5;
  static const maxSearch=Duration(minutes:3);
  static const perCandidateLimit=Duration(seconds:95);
  bool _cancelled=false;
  BenchmarkStreamResolver? _activeResolver;
  TikTokDownloader? _activeTikTok;
  void cancel(){
    _cancelled=true;
    _activeResolver?.cancel();
    _activeTikTok?.cancel();
    Native.call('cancelTextScan');
  }
  void _check(){if(_cancelled)throw const OneClickCancelled();}
  
  static String? youtubeId(String link){
    final uri=Uri.tryParse(link);
    if(uri==null)return null;
    String? id;
    if(uri.host.endsWith('youtube.com')){
      if(uri.path=='/watch')id=uri.queryParameters['v'];
      if(uri.path.startsWith('/shorts/'))id=uri.pathSegments.length>=2?uri.pathSegments[1]:null;
    }
    if(uri.host=='youtu.be'&&uri.pathSegments.isNotEmpty)id=uri.pathSegments.first;
    return id!=null&&RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)?id:null;
  }

  Future<CandidateCheck> inspect(BenchOrigin origin,List<dynamic> reference)async{
    _check();
    String? path;
    Clip? downloaded;
    var retainDownloaded=false;
    final id=youtubeId(origin.url);
    try{
      if(id!=null){
        report('원본 후보 실제 영상 검사 · YouTube');
        path=await Native.call<String>('benchmarkStreamCachePath',{'id':id});
        if(path==null)throw StateError('임시 다운로드 경로 없음');
        _activeResolver=BenchmarkStreamResolver();
        await _activeResolver!.download(id,path,(msg)=>report(msg));
        _check();
      }else if(tiktokUrl(origin.url)!=null){
        report('원본 후보 실제 영상 검사 · TikTok');
        final d=TikTokDownloader();
        _activeTikTok=d;
        try{
          downloaded=Clip.fromJson(await d.download(origin.url,
            (value,message)=>report(message),minDuration:5,maxDuration:60));
        }finally{d.cancel();_activeTikTok=null;}
        _check();
        path=downloaded.path;
      }else{
        return CandidateCheck(origin,'unsupported','이 플랫폼은 아직 자동 영상 스트림 확인을 지원하지 않아요.');
      }
      if(path==null||path.isEmpty)throw StateError('검증할 영상 파일이 없어요.');
      _check();
      final raw=await Native.call<Map<dynamic,dynamic>>('benchmarkInspectCandidate',{'path':path})
        .timeout(const Duration(seconds:75));
      _check();
      if(raw==null)throw StateError('영상 프레임 검사 결과 없음');
      final frames=raw['frames'] as List? ?? [];
      final match=VideoMatch.match(reference,frames);
      if(!VideoMatch.strong(match)){
        return CandidateCheck(origin,'unrelated',
          '실제 영상 비교에서 불일치 · 일치 장면 ${match.matched}개, 최저 해시 거리 ${match.best}/64');
      }
      if(raw['text'] is! Map){
        return CandidateCheck(origin,'error','장면은 일치했지만 기존 자막 검사에 실패해 보류합니다.');
      }
      if(OverlayCheck.suspicious(raw['text'] as Map)){
        return CandidateCheck(origin,'overlay','영상은 일치하지만 기존 자막·상단 제목이 의심돼 제외합니다.');
      }
      retainDownloaded=true;
      return CandidateCheck(origin,'checked',
        '실제 영상 ${match.matched}개 장면 교차일치 · 자막 의심 신호 미검출 (수동 최종 확인 권장)',
        clip:downloaded);
    }on OneClickCancelled{
      rethrow;
    }catch(e){
      if(_cancelled)throw const OneClickCancelled();
      return CandidateCheck(origin,'error','후보 영상 확인 실패: $e');
    }finally{
      _activeResolver=null;_activeTikTok=null;
      if(downloaded!=null&&!retainDownloaded){
        try{await Native.call('deleteLocalVideo',
          {'paths':[downloaded.path,downloaded.thumbnail]});}catch(_){}
      }
      if(id!=null&&path!=null){
        try{final f=File(path);if(await f.exists())await f.delete();}catch(_){}
      }
    }
  }

  Future<OneClickResult> run(String benchmarkId,List<dynamic> frames)async{
    final watch=Stopwatch()..start();
    _check();
    report('1/3 · 주요 장면으로 웹 이미지 후보 검색 중');
    final finder=FrameReverseSearch(apiKey);
    List<BenchOrigin> discovered;
    try{
      discovered=await finder.discover(benchmarkId,frames)
        .timeout(const Duration(seconds:95));
      _check();
    }
    finally{finder.close();}
    if(discovered.isEmpty){
      return const OneClickResult([],total:0,inspected:0);
    }
    final results=<CandidateCheck>[];
    var checked=0;
    for(final origin in discovered){
      _check();
      if(checked>=maxVerifications||watch.elapsed>=maxSearch){
        report('검증 제한에 도달했어요. 나머지는 확인되지 않은 후보로 남겨요.');
        break;
      }
      if(youtubeId(origin.url)==null&&tiktokUrl(origin.url)==null)continue;
      checked++;
      report('2/3 · 후보 $checked/$maxVerifications 동영상과 기존 자막 확인 중');
      final verdict=await inspect(origin,frames).timeout(
        perCandidateLimit,onTimeout:(){
          _activeResolver?.cancel();
          _activeTikTok?.cancel();
          Native.call('cancelTextScan');
          return CandidateCheck(origin,'error','개별 후보 95초 제한 초과 · 다음 후보로 진행');
        });
      _check();
      if(verdict.status!='checked'&&verdict.clip!=null){
        try{await Native.call('deleteLocalVideo',{'paths':[verdict.clip!.path,verdict.clip!.thumbnail]});}
        catch(_){}
      }
      results.add(verdict);
      // A confirmed, caption-screened TikTok source is sufficient for
      // one-click editor handoff. Avoid downloading additional candidates.
      if(verdict.status=='checked'&&verdict.clip!=null)break;
    }
    for(final origin in discovered){
      if(results.any((c)=>c.origin.url==origin.url))continue;
      results.add(CandidateCheck(origin,'unverified','영상 프레임 미검증 · 관련 페이지라는 사실만 확인됨'));
    }
    _check();
    report('3/3 · 실제 영상 대조 결과 정리 중');
    results.sort((a,b){
      int weight(String s)=>switch(s){'checked'=>0,'overlay'=>1,'unverified'=>2,'unsupported'=>3,_=>4};
      return weight(a.status).compareTo(weight(b.status));
    });
    return OneClickResult(results,total:discovered.length,inspected:checked);
  }
}
