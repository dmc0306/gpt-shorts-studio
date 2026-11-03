import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'benchmark_data.dart';
import 'benchmark_duration.dart';
import 'benchmark_stream.dart';
import 'bridge.dart';
import 'model.dart';
import 'tiktok_download.dart';
import 'vision_reverse.dart';

class OneClickCancelled implements Exception {
  const OneClickCancelled();
  @override String toString()=> '원본 탐색을 중단했어요.';
}

/// Condense external extractor debug HTML and platform internals into
/// actionable, bounded messages. Never log raw provider page bodies in UI.
class CandidateFailure {
  static String describe(Object error){
    final raw=error.toString();
    final lower=raw.toLowerCase();
    if(raw.contains('10204')||raw.contains('PAGE_UNAVAILABLE')){
      return 'TikTok에서 후보 영상 정보를 가져오지 못했어요 (추출기 오류 10204). 공개 페이지가 표시되더라도 영상 스트림 접근은 별도로 막힐 수 있어요.';
    }
    if(lower.contains('403')||lower.contains('forbidden')){
      return '영상 스트림 요청이 HTTP 403으로 거절됐어요. 현재 다운로드 경로의 접근 제한 가능성이 있어요.';
    }
    if(lower.contains('85초')||lower.contains('95초')||
       lower.contains('timeout')||lower.contains('time out')){
      return '후보 영상 스트림 확인 제한시간 초과. 원본 영상 일치 여부는 아직 알 수 없어요.';
    }
    if(lower.contains('취소')||lower.contains('cancel')){
      return '후보 영상 스트림 연결이 취소됐어요. 원본 일치 여부는 미확인입니다.';
    }
    final cleaned=raw.replaceAll(RegExp(r'\s+'),' ').trim();
    return cleaned.length<=170?cleaned:'${cleaned.substring(0,170)}… (상세 로그 생략)';
  }
}

class CandidateCheck {
  const CandidateCheck(this.origin,this.status,this.detail,{this.clip});
  final BenchOrigin origin;
  final String status; // checked, overlay, unrelated, unsupported, error
  final String detail;
  final Clip? clip;
}

class OneClickResult {
  const OneClickResult(this.results,{required this.total,required this.inspected,
    required this.diagnostic});
  final List<CandidateCheck> results;
  final int total,inspected;
  final String diagnostic;
  CandidateCheck? get best {
    for(final r in results){if(r.status=='checked'&&r.clip!=null)return r;}
    return null;
  }
  CandidateCheck? get match {
    for(final r in results){if(r.status=='checked')return r;}
    return null;
  }
}

/// Each reference frame may correlate with a different original clip in a
/// compilation. Two *distinct* scenes with low dHash distance are required.
class VideoMatch {
  static int distance(String a,String b){
    if(!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(a)||
       !RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(b))return 64;
    var diff=BigInt.parse(a,radix:16)^BigInt.parse(b,radix:16);
    var bits=0;
    while(diff>BigInt.zero){diff=diff&(diff-BigInt.one);bits++;}
    return bits;
  }
  /// Same crop, distinct scenes, chronological order; one moment counts once.
  static ({int matched,int best,int distinctCandidate}) match(
      List<dynamic> reference,List<dynamic> candidate){
    final uniqueRefs=<({int crop,String hash})>[];
    for(var i=0;i<reference.length;i++){
      final item=reference[i];
      if(item is! Map)continue;
      final hash=item['hash'] as String? ?? '';
      if(distance(hash,hash)!=0||(item['contrast'] as num? ?? 0)<15)continue;
      if(uniqueRefs.any((r)=>distance(r.hash,hash)<10))continue;
      uniqueRefs.add((crop:i,hash:hash));
    }
    final hits=<({int ref,int time,int distance})>[];
    for(var i=0;i<uniqueRefs.length;i++){
      final r=uniqueRefs[i];
      for(final sample in candidate){
        if(sample is! Map||sample['cropIndex'] is! num||
           sample['timeMs'] is! num)continue;
        if((sample['cropIndex'] as num).toInt()!=r.crop)continue;
        if((sample['contrast'] as num? ?? 0)<15)continue;
        final hash=sample['hash'] as String? ?? '';
        final d=distance(r.hash,hash);
        if(d<=6)hits.add((ref:i,
          time:(sample['timeMs'] as num).toInt(),distance:d));
      }
    }
    hits.sort((a,b){
      final c=a.ref.compareTo(b.ref);
      return c!=0?c:a.time.compareTo(b.time);
    });
    final counts=List<int>.filled(hits.length,1);
    final sums=List<int>.generate(hits.length,(i)=>hits[i].distance);
    var longest=0,leastSum=1<<30,best=64;
    for(var i=0;i<hits.length;i++){
      for(var j=0;j<i;j++){
        if(hits[j].ref>=hits[i].ref||
           hits[j].time+500>hits[i].time)continue;
        final next=counts[j]+1;
        final nextSum=sums[j]+hits[i].distance;
        if(next>counts[i]||(next==counts[i]&&nextSum<sums[i])){
          counts[i]=next;sums[i]=nextSum;
        }
      }
      if(counts[i]>longest||(counts[i]==longest&&sums[i]<leastSum)){
        longest=counts[i];leastSum=sums[i];
      }
      if(hits[i].distance<best)best=hits[i].distance;
    }
    return(matched:longest,best:best,distinctCandidate:longest);
  }
  static bool strong(({int matched,int best,int distinctCandidate}) m)=>
    m.matched>=3&&m.distinctCandidate>=3&&m.best<=5;
}

/// OCR is a screening signal, not proof that the entire clip is caption-free.
/// Short-lived creator captions may appear in only one sampled scene.
class OverlayCheck {
  /// 'overlay' = repeated or highly prominent subtitle-like text.
  /// 'possible' = OCR evidence of text, but could be writing in the scene.
  /// 'unknown' = scanner failure; no automatic approval.
  /// 'clean' = no text evidence in the examined frames, not a guarantee.
  static String verdict(Map<dynamic,dynamic> ocr){
    final lines=ocr['lines'];
    if(lines is! List)return 'unknown';
    final moments=<int>{};
    final positions=<int,Set<int>>{};
    var anyText=false,centralProminent=false;
    for(final raw in lines){
      if(raw is! Map)continue;
      final y=(raw['y'] as num? ?? 0).toDouble();
      final x=(raw['x'] as num? ?? 0).toDouble();
      final width=(raw['w'] as num? ?? 0).toDouble();
      final letters=(raw['letters'] as num? ?? 0).toInt();
      final seconds=(raw['time'] as num? ?? -1).toDouble();
      if(seconds<0||letters<3||width<.14||y<.07||y>.95)continue;
      // Ignore only tiny edge watermarks; center text must not be discarded
      // just because a recognizer classified the block as a watermark.
      if(raw['watermark']==true&&width<.19&&
         (x<.12||x>.78)&&(y<.14||y>.86))continue;
      anyText=true;
      final center=x+width/2;
      final subtitleRegion=y>=.16&&y<=.87&&center>=.16&&center<=.84;
      if(!subtitleRegion)continue;
      final second=seconds.floor();
      moments.add(second);
      final cell=((y*10).round()*20)+(x*4).round();
      positions.putIfAbsent(cell,()=>{}).add(second);
      // A large short-lived central word, e.g. "feeding", is itself
      // visible pre-existing subtitle evidence.
      if(letters>=5&&width>=.22&&y>=.20&&y<=.82){
        centralProminent=true;
      }
    }
    if(centralProminent||moments.length>=2||
       positions.values.any((times)=>times.length>=2)){
      return 'overlay';
    }
    return anyText?'possible':'clean';
  }
  static bool suspicious(Map<dynamic,dynamic> ocr)=>verdict(ocr)!='clean';
}

/// YouTube thumbnail is an inexpensive *hint* when candidate stream decoding
/// is blocked. It is never accepted as proof of a matching original video.
class CandidateThumbnail {
  static int closest(List<dynamic> frames,String imageHash){
    var best=64;
    for(final entry in frames){
      if(entry is! Map)continue;
      final hash=entry['hash'];
      if(hash is! String || (entry['contrast'] as num? ?? 0)<15)continue;
      final d=VideoMatch.distance(hash,imageHash);
      if(d<best)best=d;
    }
    return best;
  }

  static Future<String> check(String videoId,List<dynamic> frames)async{
    if(!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)){
      return 'YouTube 영상 ID가 올바르지 않아요.';
    }
    final client=http.Client();
    try{
      final imageUrl=Uri.https('i.ytimg.com','/vi/$videoId/hqdefault.jpg');
      final response=await client.get(imageUrl).timeout(const Duration(seconds:9));
      if(response.statusCode!=200||response.bodyBytes.length<500||
          response.bodyBytes.length>1024*1024){
        return 'YouTube 공개 썸네일 접근 불가';
      }
      final imageHash=await Native.call<Map<dynamic,dynamic>>(
        'benchmarkFingerprintImage',{'content':base64Encode(response.bodyBytes)})
        .timeout(const Duration(seconds:8));
      if(imageHash==null || imageHash['hash'] is! String){
        return '썸네일 시각 지문 검사 실패';
      }
      final distance=closest(frames,imageHash['hash'] as String);
      if(distance<=9){
        return '공개 썸네일과 일부 장면 유사 (해시 거리 $distance/64) · 원본 확정 아님';
      }
      return '썸네일로 장면 일치 미확인 (해시 거리 $distance/64) · 다른 썸네일일 수 있음';
    }catch(_){
      return '공개 썸네일 검사 실패 · 영상 일치 여부 미확인';
    }finally{client.close();}
  }
}

class OneClickExplorer {
  OneClickExplorer(this.apiKey,this.report,{
    this.youtubeApiKey='',this.benchmarkSeconds=0,this.ignoredUrls=const {}});
  final String apiKey;
  final String youtubeApiKey;
  final int benchmarkSeconds;
  final Set<String> ignoredUrls;
  final void Function(String message) report;
  /// Distinct search windows prevent re-querying exactly the same images.
  /// Never allow an endless loop that burns API quota on identical responses.
  static List<List<dynamic>> frameBatches(List<dynamic> frames,{bool continuous=false}){
    if(frames.length<3)return [];
    final chronological=frames.toList()..sort((a,b){
      final at=a is Map?(a['timeMs'] as num? ?? 0).toInt():0;
      final bt=b is Map?(b['timeMs'] as num? ?? 0).toInt():0;
      return at.compareTo(bt);
    });
    final take=continuous?(chronological.length<5?chronological.length:5):
      (chronological.length<6?chronological.length:6);
    final rounds=continuous?(chronological.length<6?chronological.length:6):1;
    final batches=<List<dynamic>>[];
    final signatures=<String>{};
    for(var round=0;round<rounds;round++){
      final indices=<int>[
        for(var i=0;i<take;i++) (i+round)%chronological.length,
      ]..sort();
      final id=indices.join(',');
      if(!signatures.add(id))continue;
      batches.add([for(final index in indices)chronological[index]]);
    }
    return batches;
  }

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

  /// Prioritize direct image matches, not simply platform or clip duration.
  static int evidenceScore(BenchOrigin origin){
    if(origin.source!='이미지 직접일치 후보')return 0;
    final moments=RegExp(r'직접 이미지 일치 근거 (\d+)개 장면')
      .firstMatch(origin.evidence);
    final full=RegExp(r'완전 일치 (\d+)개').firstMatch(origin.evidence);
    final n=int.tryParse(moments?.group(1)??'0')??0;
    final f=int.tryParse(full?.group(1)??'0')??0;
    return n.clamp(0,10).toInt()*10+f.clamp(0,10).toInt()*3;
  }

  Future<CandidateCheck> inspect(BenchOrigin origin,List<dynamic> reference)async{
    _check();
    String? path;
    Clip? downloaded;
    var retainDownloaded=false;
    final id=youtubeId(origin.url);
    var imageHint='';
    try{
      if(id!=null){
        report('원본 후보 YouTube 공개 썸네일 사전 비교 중');
        imageHint=await CandidateThumbnail.check(id,reference);
        report(imageHint);
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
          final delta=BenchmarkDuration.tolerance(benchmarkSeconds);
          final minSec=benchmarkSeconds>0?(benchmarkSeconds-delta).clamp(5,600).toDouble():5.0;
          final maxSec=benchmarkSeconds>0?(benchmarkSeconds+delta).clamp(5,600).toDouble():60.0;
          downloaded=Clip.fromJson(await d.download(origin.url,
            (value,message)=>report(message),minDuration:minSec,maxDuration:maxSec));
        }finally{d.cancel();_activeTikTok=null;}
        _check();
        path=downloaded.path;
      }else{
        return CandidateCheck(origin,'unsupported','이 플랫폼은 아직 자동 영상 스트림 확인을 지원하지 않아요.');
      }
      if(path==null||path.isEmpty)throw StateError('검증할 영상 파일이 없어요.');
      _check();
      final bounds=<Map<String,double>>[];
      for(final item in reference){
        if(item is Map && item['bounds'] is Map){
          final b=item['bounds'] as Map;
          if(['x','y','w','h'].every((k)=>b[k] is num)){
            bounds.add({for(final k in ['x','y','w','h'])k:(b[k] as num).toDouble()});
          }
        }
      }
      final raw=await Native.call<Map<dynamic,dynamic>>('benchmarkInspectCandidate',
        {'path':path,'bounds':bounds})
        .timeout(const Duration(seconds:75));
      _check();
      if(raw==null)throw StateError('영상 프레임 검사 결과 없음');
      final frames=raw['frames'] as List? ?? [];
      final actualMs=frames.isNotEmpty&&frames.first is Map
        ?(frames.first as Map)['durationMs'] as num?:null;
      final actualSec=actualMs==null?null:(actualMs.toDouble()/1000).round();
      if(actualSec==null){
        return CandidateCheck(origin,'duration','실제 영상 길이 확인 불가 · 자동 판정 보류');
      }
      final info=frames.isNotEmpty&&frames.first is Map?frames.first as Map:null;
      final width=(info?['videoWidth'] as num?)?.toInt();
      final height=(info?['videoHeight'] as num?)?.toInt();
      if(!BenchmarkDuration.isShortGeometry(actualSec,width,height)){
        return CandidateCheck(origin,'longform',
          '롱폼/가로 영상 제외 · ${actualSec}초 · 해상도 ${width??'?'}×${height??'?'} · 세로형 또는 정사각형 최대 180초만 허용');
      }
      if(benchmarkSeconds>0&&!BenchmarkDuration.similar(benchmarkSeconds,actualSec)){
        return CandidateCheck(origin,'duration',
          BenchmarkDuration.label(benchmarkSeconds,actualSec));
      }
      final match=VideoMatch.match(reference,frames);
      if(!VideoMatch.strong(match)){
        return CandidateCheck(origin,'unrelated',
          '실제 영상 비교에서 불일치 · 일치 장면 ${match.matched}개, 최저 해시 거리 ${match.best}/64');
      }
      if(raw['text'] is! Map){
        return CandidateCheck(origin,'error','장면은 일치했지만 기존 자막 검사에 실패해 보류합니다.');
      }
      final textStatus=OverlayCheck.verdict(raw['text'] as Map);
      if(textStatus=='overlay'){
        return CandidateCheck(origin,'overlay',
          '영상 장면은 일치하지만 기존 자막/화면 글자 감지 · 무자막 원본으로 자동 승인하지 않음');
      }
      if(textStatus!='clean'){
        return CandidateCheck(origin,'caption_possible',
          '영상 장면은 일치하지만 일부 글자 감지 또는 OCR 불확실 · 직접 영상 확인 필요');
      }
      retainDownloaded=true;
      return CandidateCheck(origin,'checked',
        '실제 영상 ${match.matched}개 장면 교차일치 · 자막 의심 신호 미검출 (수동 최종 확인 권장)',
        clip:downloaded);
    }on OneClickCancelled{
      rethrow;
    }catch(e){
      if(_cancelled)throw const OneClickCancelled();
      return CandidateCheck(origin,'error',
        '후보 영상 확인 실패: ${CandidateFailure.describe(e)}'
        '${imageHint.isNotEmpty?' · $imageHint':''}');
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
    VisionSearchReport discovery;
    try{
      discovery=await finder.discoverReport(benchmarkId,frames)
        .timeout(const Duration(seconds:95));
      _check();
    }
    finally{finder.close();}
    report(discovery.diagnostic);
    final discovered=discovery.candidates.where((c)=>
      !ignoredUrls.contains(c.url)).toList();
    if(discovered.isEmpty){
      return OneClickResult(const [],total:0,inspected:0,
        diagnostic:discovery.diagnostic);
    }
    report('2/3 · YouTube 후보의 실제 재생시간 조회 및 유사 길이 우선 정렬 중');
    final allIds=discovered.where((o)=>o.source!='연관 페이지만 확인')
      .map((o)=>youtubeId(o.url)).whereType<String>();
    final lengths=await BenchmarkDuration.youtubeLengths(youtubeApiKey,allIds);
    _check();
    int priority(BenchOrigin item){
      if(item.source=='연관 페이지만 확인')return 10000;
      final id=youtubeId(item.url);
      if(id!=null&&benchmarkSeconds>0){
        final duration=lengths[id];
        if(duration==null)return 9000;
        if(!BenchmarkDuration.similar(benchmarkSeconds,duration))return 9500;
      }
      if(id==null&&tiktokUrl(item.url)==null)return 8000;
      return 1000-evidenceScore(item)*10+(id!=null?0:1);
    }
    final ordered=discovered.toList()..sort((a,b)=>priority(a).compareTo(priority(b)));
    final results=<CandidateCheck>[];
    var checked=0;
    var youtubeStreamBlocked=false;
    for(final origin in ordered){
      _check();
      if(checked>=maxVerifications||watch.elapsed>=maxSearch){
        report('검증 제한에 도달했어요. 나머지는 확인되지 않은 후보로 남겨요.');
        break;
      }
      if(origin.source=='연관 페이지만 확인'){
        results.add(CandidateCheck(origin,'weak',
          '이미지를 포함한다는 직접 근거가 없는 웹페이지 · '
          '원본 후보로 검증하지 않고 수동 참고용으로만 표시'));
        continue;
      }
      final candidateYoutubeId=youtubeId(origin.url);
      if(candidateYoutubeId==null&&tiktokUrl(origin.url)==null){
        final host=Uri.tryParse(origin.url)?.host??'외부 서비스';
        results.add(CandidateCheck(origin,'unsupported',
          '$host 게시물의 이미지 일치 근거만 확보 · 실제 동영상 스트림/영상 길이/기존 자막은 검사하지 못했음 · 무자막 원본으로 확정 불가'));
        continue;
      }
      if(candidateYoutubeId!=null){
        final duration=lengths[candidateYoutubeId];
        if(duration!=null&&!BenchmarkDuration.isShort(duration)){
          results.add(CandidateCheck(origin,'longform',
            'YouTube 롱폼 제외 · ${duration}초 · 최대 180초만 검사'));
          continue;
        }
        if(duration==null){
          results.add(CandidateCheck(origin,'duration',
            'YouTube 공식 API로 후보 길이를 확인하지 못해 다운로드하지 않았어요. YouTube Data API 키 설정을 확인해 주세요.'));
          continue;
        }
        if(benchmarkSeconds>0&&!BenchmarkDuration.similar(benchmarkSeconds,duration)){
          results.add(CandidateCheck(origin,'duration',
            BenchmarkDuration.label(benchmarkSeconds,duration)+' · 자동 확인에서 제외'));
          continue;
        }
        report('후보 길이 조건 통과 · ${BenchmarkDuration.label(benchmarkSeconds,duration)}');
      }
      if(candidateYoutubeId!=null&&youtubeStreamBlocked){
        report('YouTube 스트림 문제로 동일 플랫폼의 반복 다운로드 생략');
        final imageHint=await CandidateThumbnail.check(candidateYoutubeId,frames);
        results.add(CandidateCheck(origin,'error',
          '같은 실행에서 YouTube 스트림 접근 실패 · 반복 85초 다운로드 생략 · $imageHint'));
        continue;
      }
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
      if(candidateYoutubeId!=null&&verdict.status=='error'&&
         (verdict.detail.contains('스트림')||verdict.detail.contains('85초')||
          verdict.detail.contains('연결')||verdict.detail.contains('YouTube'))){
        youtubeStreamBlocked=true;
      }
      // A confirmed, caption-screened TikTok source is sufficient for
      // one-click editor handoff. Avoid downloading additional candidates.
      if(verdict.status=='checked'&&verdict.clip!=null)break;
    }
    for(final origin in discovered){
      if(results.any((c)=>c.origin.url==origin.url))continue;
      results.add(CandidateCheck(origin,'unverified',
        '검색 후보는 발견했지만 이번 검색의 검증 시간/횟수 한도에 도달 · 실제 영상과 자막 미확인'));
    }
    _check();
    report('3/3 · 실제 영상 대조 결과 정리 중');
    results.sort((a,b){
      int weight(String s)=>switch(s){
        'checked'=>0,'overlay'=>1,'caption_possible'=>2,'duration'=>3,
        'longform'=>4,'unsupported'=>5,'unverified'=>6,'weak'=>8,_=>7};
      return weight(a.status).compareTo(weight(b.status));
    });
    final verified=results.where((r)=>r.status=='checked').length;
    final rejected=results.where((r)=>r.status=='unrelated').length;
    final overlay=results.where((r)=>r.status=='overlay').length;
    final captionPossible=results.where((r)=>r.status=='caption_possible').length;
    final unsupported=results.where((r)=>r.status=='unsupported').length;
    final failures=results.where((r)=>r.status=='error').length;
    final durationSkipped=results.where((r)=>r.status=='duration').length;
    final longformSkipped=results.where((r)=>r.status=='longform').length;
    final directLeads=discovered.where((o)=>o.source=='이미지 직접일치 후보').length;
    final weakLeads=discovered.where((o)=>o.source=='연관 페이지만 확인').length;
    final diagnostic='${discovery.diagnostic} 직접 이미지 일치 후보 $directLeads건 · '
      '단순 관련 페이지 $weakLeads건(자동 확인 제외) · 실제 영상 검사 $checked건 · '
      '장면·자막 검증 통과 $verified건 · 불일치 $rejected건 · '
      '기존 자막 감지 $overlay건 · 글자 감지/확인 보류 $captionPossible건 · '
      '플랫폼 영상 검사 미지원 $unsupported건 · 길이 불일치/미확인 $durationSkipped건 · '
      '롱폼/가로 영상 제외 $longformSkipped건 · 처리 실패 $failures건.';
    report(diagnostic);
    return OneClickResult(results,total:discovered.length,inspected:checked,
      diagnostic:diagnostic);
  }
}
