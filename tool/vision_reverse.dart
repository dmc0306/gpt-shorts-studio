import 'dart:convert';
import 'package:http/http.dart' as http;
import 'benchmark_data.dart';

/// Reverse lookup only: no title, description or textual keywords are sent.
/// Image bytes are sent to Google Cloud Vision WEB_DETECTION.
/// Evidence counters from the one-click Web Detection response.
/// Counts describe Google's web index, not verified original videos.
class VisionSearchReport {
  const VisionSearchReport({required this.candidates,required this.frames,
    required this.pages,required this.pagesWithEvidence,
    required this.socialPosts,required this.indexedImages});
  final List<BenchOrigin> candidates;
  final int frames,pages,pagesWithEvidence,socialPosts,indexedImages;
  String get diagnostic {
    if(pages==0)return 'Cloud Vision이 검색한 영상 프레임 $frames장 중 이미지 일치 웹페이지가 0개입니다. 이 영상의 장면이 웹 이미지 검색에 색인되지 않았을 수 있어요.';
    if(socialPosts==0)return 'Cloud Vision 응답: 일치 웹페이지 $pages건 · 직접 이미지 일치 근거 $pagesWithEvidence건 · TikTok/Instagram/YouTube 개별 게시물 0건. 검색 엔진에 영상 게시물이 연결되지 않았어요.';
    return 'Cloud Vision 응답: 이미지 검색 $frames장 · 일치 웹페이지 $pages건 · 직접 이미지 일치 근거 $pagesWithEvidence건 · 소셜 게시물 단서 $socialPosts건 · 원본 후보 ${candidates.length}건.';
  }
}

class FrameReverseSearch {
  FrameReverseSearch(this.apiKey,{http.Client? client}):_client=client??http.Client();
  final String apiKey;
  final http.Client _client;
  void close()=>_client.close();


  /// Precision-first matching. A web page listed in pagesWithMatchingImages
  /// alone is not evidence that the linked social video is the same video.
  /// Demand page-local full/partial image matches at 3 distinct time points,
  /// including >=1 full match. Otherwise return an honest empty result.
  static List<BenchOrigin> rank(Object? value,String benchmarkId){
    if(value is! List)throw const FormatException('Vision 응답 목록이 올바르지 않아요.');
    final evidence=<String,Map<int,int>>{};
    for(var index=0;index<value.length;index++){
      final response=value[index];
      if(response is! Map)continue;
      if(response['error'] is Map){
        final error=response['error'] as Map;
        throw StateError('Vision WEB_DETECTION 오류 · 코드 ${error['code']??'unknown'}');
      }
      final web=response['webDetection'];
      if(web is! Map)continue;
      final pages=web['pagesWithMatchingImages'];
      if(pages is! List)continue;
      for(final page in pages){
        if(page is! Map)continue;
        final url=normalOrigin(page['url'] as String? ?? '');
        if(url==null)continue;
        final uri=Uri.tryParse(url);
        if(uri!=null && ((uri.path=='/watch'&&uri.queryParameters['v']==benchmarkId)||
            uri.path=='/shorts/$benchmarkId'))continue;
        final full=page['fullMatchingImages'];
        final partial=page['partialMatchingImages'];
        final exact=full is List&&full.any((image)=>image is Map&&image['url'] is String);
        final cropped=partial is List&&partial.any((image)=>image is Map&&image['url'] is String);
        if(!exact&&!cropped)continue; // Page relation alone is insufficient.
        final category=exact?2:1;
        final moments=evidence.putIfAbsent(url,()=>{});
        if(category>(moments[index]??0))moments[index]=category;
      }
    }
    final qualified=evidence.entries.where((entry){
      final frames=entry.value;
      return frames.length>=3 && frames.values.any((level)=>level==2);
    }).toList();
    qualified.sort((a,b){
      final fullA=a.value.values.where((n)=>n==2).length;
      final fullB=b.value.values.where((n)=>n==2).length;
      final byFull=fullB.compareTo(fullA);
      return byFull!=0?byFull:b.value.length.compareTo(a.value.length);
    });
    return qualified.take(12).map((entry){
      final count=entry.value.length;
      final fullCount=entry.value.values.where((n)=>n==2).length;
      return BenchOrigin(entry.key,
        '서로 다른 $count개 시점에서 직접 이미지 매칭 (완전 일치 $fullCount개 시점) · 실제 동일 영상 여부는 확인 필요',
        '직접일치 교차검증 v2');
    }).toList();
  }

  /// Broad discovery is separate from source confirmation. One matching frame
  /// is enough to *investigate* a video, never to label it verified.
  static List<BenchOrigin> discoveryCandidates(Object? input,String benchmarkId){
    if(input is! List)throw const FormatException('Vision 후보 검색 응답 오류');
    final scores=<String,int>{};
    final hits=<String,Set<int>>{};
    for(var i=0;i<input.length;i++){
      final response=input[i];
      if(response is! Map)continue;
      if(response['error'] is Map){
        throw StateError('Vision 검색 응답 오류 · ${(response['error'] as Map)['code']??'unknown'}');
      }
      final web=response['webDetection'];
      if(web is! Map)continue;
      final pages=web['pagesWithMatchingImages'];
      if(pages is! List)continue;
      for(final page in pages){
        if(page is! Map)continue;
        final url=normalOrigin(page['url'] as String? ?? '');
        if(url==null)continue;
        final uri=Uri.tryParse(url);
        if(uri!=null&&((uri.path=='/watch'&&uri.queryParameters['v']==benchmarkId)||
            uri.path=='/shorts/$benchmarkId'))continue;
        final full=page['fullMatchingImages'];
        final partial=page['partialMatchingImages'];
        final direct=full is List&&full.isNotEmpty;
        final cropped=partial is List&&partial.isNotEmpty;
        final quality=direct?3:cropped?2:1;
        final byMoment=hits.putIfAbsent(url,()=>{});
        if(byMoment.add(i))scores[url]=(scores[url]??0)+quality;
      }
    }
    final sorted=scores.keys.toList()..sort((a,b){
      final byScore=scores[b]!.compareTo(scores[a]!);
      return byScore==0?(hits[b]!.length.compareTo(hits[a]!.length)):byScore;
    });
    return sorted.take(24).map((url)=>BenchOrigin(url,
      '이미지 검색에서 ${hits[url]!.length}개 장면의 페이지 후보로 발견됨 · 영상 프레임 대조 전 · 원본 확정 아님',
      '역이미지 탐색 후보')).toList();
  }

  Future<List<BenchOrigin>> discover(String benchmarkId,List<dynamic> frames) async {
    return (await discoverReport(benchmarkId,frames)).candidates;
  }

  Future<VisionSearchReport> discoverReport(String benchmarkId,List<dynamic> frames)async {
    final raw=await _responses(frames);
    var pages=0,withEvidence=0,social=0,images=0;
    for(final response in raw){
      if(response is! Map)continue;
      final web=response['webDetection'];
      if(web is! Map)continue;
      for(final key in ['fullMatchingImages','partialMatchingImages','visuallySimilarImages']){
        final items=web[key];
        if(items is List)images+=items.length;
      }
      final matched=web['pagesWithMatchingImages'];
      if(matched is! List)continue;
      pages+=matched.length;
      for(final item in matched){
        if(item is! Map)continue;
        final full=item['fullMatchingImages'],partial=item['partialMatchingImages'];
        if((full is List&&full.isNotEmpty)||(partial is List&&partial.isNotEmpty))withEvidence++;
        if(normalOrigin(item['url'] as String? ?? '')!=null)social++;
      }
    }
    return VisionSearchReport(candidates:discoveryCandidates(raw,benchmarkId),
      frames:frames.length,pages:pages,pagesWithEvidence:withEvidence,
      socialPosts:social,indexedImages:images);
  }

  Future<List<dynamic>> _responses(List<dynamic> frames)async{
    if(apiKey.trim().isEmpty)throw StateError('Google Cloud Vision API 키를 입력해 주세요.');
    if(frames.isEmpty||frames.length>10)throw StateError('검색할 주요 장면이 없거나 개수가 너무 많아요.');
    final requests=<Map<String,dynamic>>[];
    for(final raw in frames){
      if(raw is! Map||raw['content'] is! String)throw const FormatException('추출 이미지 데이터 오류');
      final content=raw['content'] as String;
      if(content.length<100||content.length>1_500_000)throw const FormatException('추출 이미지가 너무 커요.');
      requests.add({'image':{'content':content},
         'features':[{'type':'WEB_DETECTION','maxResults':30}]});
    }
    final response=await _client.post(Uri.https('vision.googleapis.com','/v1/images:annotate',{'key':apiKey}),
      headers:{'Content-Type':'application/json'},
      body:jsonEncode({'requests':requests})).timeout(const Duration(seconds:90));
    if(response.statusCode!=200)throw StateError('Cloud Vision HTTP ${response.statusCode}');
    final decoded=jsonDecode(response.body);
    if(decoded is! Map||decoded['responses'] is! List)throw const FormatException('Vision API 응답 오류');
    return decoded['responses'] as List;
  }

  Future<List<BenchOrigin>> find(String benchmarkId,List<dynamic> frames)async {
    return rank(await _responses(frames),benchmarkId);
  }
}
