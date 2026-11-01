import 'dart:convert';
import 'package:http/http.dart' as http;
import 'benchmark_data.dart';

/// Reverse lookup only: no title, description or textual keywords are sent.
/// Image bytes are sent to Google Cloud Vision WEB_DETECTION.
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

  Future<List<BenchOrigin>> find(String benchmarkId,List<dynamic> frames)async{
    if(apiKey.trim().isEmpty)throw StateError('Google Cloud Vision API 키를 입력해 주세요.');
    if(frames.isEmpty||frames.length>10)throw StateError('검색할 주요 장면이 없거나 개수가 너무 많아요.');
    final requests=<Map<String,dynamic>>[];
    for(final raw in frames){
      if(raw is! Map || raw['content'] is! String)throw const FormatException('추출 장면 데이터 오류');
      final content=raw['content'] as String;
      if(content.length<100||content.length>1_500_000)throw const FormatException('추출 장면 이미지 크기가 올바르지 않아요.');
      requests.add({'image':{'content':content},
        'features':[{'type':'WEB_DETECTION','maxResults':25}]});
    }
    final res=await _client.post(
      Uri.https('vision.googleapis.com','/v1/images:annotate',{'key':apiKey}),
      headers:{'Content-Type':'application/json'},
      body:jsonEncode({'requests':requests})).timeout(const Duration(seconds:90));
    if(res.statusCode!=200)throw StateError('Google Cloud Vision HTTP ${res.statusCode} · API 활성화, 키 제한, 결제 설정을 확인해 주세요.');
    final decoded=jsonDecode(res.body);
    if(decoded is! Map || decoded['responses'] is! List)throw const FormatException('Vision API 응답 형식 오류');
    return rank(decoded['responses'],benchmarkId);
  }
}
