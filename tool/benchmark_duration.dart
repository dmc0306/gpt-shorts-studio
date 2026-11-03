import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Duration evidence gates downloads, but never proves two videos are identical.
class BenchmarkDuration {
  // A small absolute allowance handles platform rounding and short clips.
  // A 42-second reference now accepts 37–47 seconds, rather than 33–51 seconds.
  static int tolerance(int seconds)=>max(2,(seconds*.10).ceil());
  static bool isShort(int seconds)=>seconds>0&&seconds<=60;
  /// Deliberately excludes 61–180 s Shorts to reduce longform false positives.
  /// API duration alone does not prove YouTube Shorts classification.
  /// Downloaded vertical or square geometry is required as an extra gate.
  static bool isShortGeometry(int seconds,int? width,int? height)=>
    isShort(seconds)&&width!=null&&height!=null&&width>0&&height>0&&width<=height;
  static bool similar(int reference,int candidate)=>
    reference>0&&candidate>0&&(reference-candidate).abs()<=tolerance(reference);
  static String label(int reference,int? candidate){
    if(candidate==null)return '길이 확인 불가';
    final gap=(candidate-reference).abs();
    return similar(reference,candidate)
      ?'길이 일치 범위 · 기준 $reference초 / 후보 $candidate초 (차이 $gap초)'
      :'길이 불일치 · 기준 $reference초 / 후보 $candidate초 (차이 $gap초, 허용 ±${tolerance(reference)}초)';
  }
  static int? iso8601(String? raw){
    if(raw==null)return null;
    final r=RegExp(r'^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$');
    final m=r.firstMatch(raw);
    if(m==null)return null;
    final days=int.tryParse(m.group(1)??'0')??0;
    final hours=int.tryParse(m.group(2)??'0')??0;
    final minutes=int.tryParse(m.group(3)??'0')??0;
    final seconds=double.tryParse(m.group(4)??'0')??0;
    return (days*86400+hours*3600+minutes*60+seconds).round();
  }
  static Future<Map<String,int>> youtubeLengths(String key,Iterable<String> ids)async{
    final valid=ids.where((id)=>RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)).toSet().take(50).toList();
    if(key.isEmpty||valid.isEmpty)return {};
    final client=http.Client();
    try{
      final uri=Uri.https('www.googleapis.com','/youtube/v3/videos',
        {'part':'contentDetails','id':valid.join(','),'key':key});
      final response=await client.get(uri).timeout(const Duration(seconds:14));
      if(response.statusCode!=200)return {};
      final body=jsonDecode(response.body);
      if(body is! Map||body['items'] is! List)return {};
      final result=<String,int>{};
      for(final entry in body['items'] as List){
        if(entry is! Map)continue;
        final id=entry['id'] as String?;
        final details=entry['contentDetails'];
        if(id==null||details is! Map)continue;
        final length=iso8601(details['duration'] as String?);
        if(length!=null&&length>0)result[id]=length;
      }
      return result;
    }catch(_){return {};}finally{client.close();}
  }
}
