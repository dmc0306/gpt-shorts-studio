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

  static List<BenchOrigin> rank(Object? value,String benchmarkId){
    if(value is! List)throw const FormatException('Vision 응답 목록이 올바르지 않아요.');
    final scores=<String,double>{},times=<String,Set<int>>{};
    for(var i=0;i<value.length;i++){
      final result=value[i];
      if(result is! Map)continue;
      if(result['error'] is Map){
        final error=result['error'] as Map;
        throw StateError('Vision WEB_DETECTION 오류 · 코드 ${error['code']??'unknown'}');
      }
      final web=result['webDetection'];
      if(web is! Map)continue;
      final pages=web['pagesWithMatchingImages'];
      if(pages is! List)continue;
      final urls=<String>{};
      for(final p in pages){
        if(p is! Map)continue;
        final u=normalOrigin(p['url'] as String? ?? '');
        if(u==null||!urls.add(u))continue;
        if(u.contains('/watch?v=$benchmarkId')||u.contains('/shorts/$benchmarkId'))continue;
        final score=(p['score'] as num? ?? 0.0).toDouble().clamp(0.0,3.0);
        scores[u]=(scores[u]??0)+1.0+score;
        times.putIfAbsent(u,()=>{}).add(i);
      }
    }
    final urls=scores.keys.toList()..sort((a,b){
      final byFrame=(times[b]?.length??0).compareTo(times[a]?.length??0);
      return byFrame!=0?byFrame:(scores[b]??0).compareTo(scores[a]??0);
    });
    return urls.take(30).map((url){
      final count=times[url]!.length;
      return BenchOrigin(url,'서로 다른 이미지 $count장과 일치하는 웹페이지 · 원제작 여부는 추가 확인 필요',
        '프레임 역이미지 검색');
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
