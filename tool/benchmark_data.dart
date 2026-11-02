import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// User-confirmed benchmark-to-original examples, kept separate from
/// automatically discovered candidates to avoid inflating search accuracy.
const benchmarkGroundTruth=<String,String>{
  'NPom9sHH2J0':'https://vt.tiktok.com/ZSp11jbJd/',
};

class BenchChannel {
  const BenchChannel(this.id,this.label);
  final String id,label;
  static const defaults=<BenchChannel>[
    BenchChannel('UCF24NMvY6K0wUUaRR2jscQA','일분일초'),
    BenchChannel('UCai3mx31iO67TY2SWPv3V2w','쇼츠츄러스'),
    BenchChannel('UCpBpsIYfgEe2s-zazZ643xw','모르면개손해'),
    BenchChannel('UCIKPuhVfWDTaCj6gJqcP7aw','숏싹숏싹'),
    BenchChannel('UCUDXfrLWHGshJQp1tYjTs5Q','그래서리뷰'),
    BenchChannel('UCVis1dx_SaAfMpiWNckmQjg','진짜좋아'),
    BenchChannel('UCE1U6r9ZlAbPe5kjqCp2W2g','잉?!'),
    BenchChannel('UCKGy4o0tdDRuyMuZEGvACWg','웃다가딱걸림'),
    BenchChannel('UC6pq9OULRLBQiZ8NyDQKIAQ','하얀낙타'),
    BenchChannel('UC80R0l6HZcgdKKG2iMyQWUw','해외반응 지식충전')];
}
class BenchVideo {
  const BenchVideo(this.id,this.channelId,this.channel,this.title,this.description,this.views,this.duration,this.publishedAt);
  final String id,channelId,channel,title,description,publishedAt;
  final int views,duration;
  String get url=>'https://www.youtube.com/watch?v=$id';
  Map<String,dynamic> toJson()=>{'id':id,'channelId':channelId,'channel':channel,'title':title,
    'description':description,'views':views,'duration':duration,'publishedAt':publishedAt};
  factory BenchVideo.fromJson(Map j)=>BenchVideo(j['id'] as String,j['channelId'] as String,
    j['channel'] as String,j['title'] as String,j['description'] as String? ?? '',
    (j['views'] as num? ?? 0).toInt(),(j['duration'] as num? ?? 0).toInt(),
    j['publishedAt'] as String? ?? '');
  static int seconds(String text){
    final m=RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(text);
    if(m==null)return 0;
    return (int.tryParse(m.group(1)??'')??0)*86400+(int.tryParse(m.group(2)??'')??0)*3600+
       (int.tryParse(m.group(3)??'')??0)*60+(int.tryParse(m.group(4)??'')??0);
  }
}
class BenchOrigin {
  const BenchOrigin(this.url,this.evidence,this.source);
  final String url,evidence,source;
  Map<String,dynamic> toJson()=>{'url':url,'evidence':evidence,'source':source};
  factory BenchOrigin.fromJson(Map j)=>BenchOrigin(j['url'] as String,
    j['evidence'] as String? ?? '',j['source'] as String? ?? '');
}
String? normalOrigin(String input){
  final u=Uri.tryParse(input.trim().replaceAll(RegExp(r'[),.!]+$'),''));
  if(u==null||u.scheme!='https'||u.userInfo.isNotEmpty||(u.hasPort&&u.port!=443))return null;
  final h=u.host.toLowerCase(),p=u.path;
  if((h=='vt.tiktok.com'||h=='vm.tiktok.com')&&
      RegExp(r'^/[a-zA-Z0-9_-]{5,32}/?$').hasMatch(p)){
    return Uri.https(h,p).toString();
  }
  if((h=='tiktok.com'||h.endsWith('.tiktok.com'))&&RegExp(r'^/@[^/]+/video/\d+/?$').hasMatch(p))return Uri.https('www.tiktok.com',p).toString();
  if((h=='instagram.com'||h.endsWith('.instagram.com'))&&RegExp(r'^/(reel|p)/[a-zA-Z0-9_-]+/?$').hasMatch(p))return Uri.https('www.instagram.com',p).toString();
  if((h=='youtube.com'||h.endsWith('.youtube.com'))&&((p=='/watch'&&u.queryParameters['v']?.isNotEmpty==true)||RegExp(r'^/shorts/[A-Za-z0-9_-]{8,}$').hasMatch(p)))return Uri.https('www.youtube.com',p,p=='/watch'?{'v':u.queryParameters['v']!}:null).toString();
  if(h=='youtu.be'&&RegExp(r'^/[A-Za-z0-9_-]{8,}$').hasMatch(p))return Uri.https('www.youtube.com','/watch',{'v':p.substring(1)}).toString();
  return null;
}
class BenchState {
  BenchState();
  final channels=<String,String>{for(final c in BenchChannel.defaults)c.id:c.label};
  final top=<String,List<BenchVideo>>{},scanned=<String,int>{},complete=<String,bool>{};
  final seen=<String>{},selected=<String>[];
  final origins=<String,List<BenchOrigin>>{},chosen=<String,String>{},rights=<String,String>{},proof=<String,String>{};
  /// User supplied, not an automated frame match.
  final confirmed=<String,String>{...benchmarkGroundTruth};
  /// Explicitly rejected source links for this benchmark video.
  final rejected=<String,Set<String>>{};
  final diagnostics=<String,String>{};
  Map<String,dynamic> toJson()=>{'channels':channels,'top':top.map((k,v)=>MapEntry(k,v.map((e)=>e.toJson()).toList())),
    'scanned':scanned,'complete':complete,'seen':seen.toList(),'selected':selected,
    'origins':origins.map((k,v)=>MapEntry(k,v.map((e)=>e.toJson()).toList())),
    'chosen':chosen,'rights':rights,'proof':proof,
    'confirmed':confirmed,
    'rejected':rejected.map((k,v)=>MapEntry(k,v.toList())),
    'diagnostics':diagnostics};
  factory BenchState.fromJson(Map raw){
    final b=BenchState();
    if(raw['channels'] is Map){b.channels.clear();(raw['channels'] as Map).forEach((k,v){if(k is String&&v is String&&RegExp(r'^UC[\w-]{22}$').hasMatch(k))b.channels[k]=v;});}
    if(raw['top'] is Map){(raw['top'] as Map).forEach((k,v){if(k is String&&v is List)b.top[k]=v.whereType<Map>().map(BenchVideo.fromJson).toList();});}
    if(raw['scanned'] is Map){(raw['scanned'] as Map).forEach((k,v){if(k is String&&v is num)b.scanned[k]=v.toInt();});}
    if(raw['complete'] is Map){(raw['complete'] as Map).forEach((k,v){if(k is String&&v is bool)b.complete[k]=v;});}
    b.seen.addAll((raw['seen'] as List? ?? []).whereType<String>());
    b.selected.addAll((raw['selected'] as List? ?? []).whereType<String>());
    if(raw['origins'] is Map){(raw['origins'] as Map).forEach((k,v){if(k is String&&v is List)b.origins[k]=v.whereType<Map>().map(BenchOrigin.fromJson).toList();});}
    for(final pair in [(raw['chosen'],b.chosen),(raw['rights'],b.rights),(raw['proof'],b.proof)]){
      final source=pair.$1,target=pair.$2;
      if(source is Map)source.forEach((k,v){if(k is String&&v is String)target[k]=v;});
    }
    if(raw['confirmed'] is Map){
      (raw['confirmed'] as Map).forEach((k,v){
        if(k is String&&v is String&&
            RegExp(r'^[A-Za-z0-9_-]{11}
      (raw['diagnostics'] as Map).forEach((k,v){
        if(k is String&&v is String)b.diagnostics[k]=v;
      });
    }
    return b;
  }
  List<BenchVideo> get picked=>[for(final id in selected)for(final list in top.values)for(final v in list)if(v.id==id)v];
  void draw(){
    selected.clear();final rng=Random.secure();
    for(final key in channels.keys){
      final available=(top[key]??[]).where((v)=>!seen.contains(v.id)).toList();
      if(available.isEmpty)continue;
      final v=available[rng.nextInt(available.length)];
      selected.add(v.id);seen.add(v.id);
    }
  }
}
class BenchApi {
  BenchApi(this.key,{http.Client? client}):client=client??http.Client();
  final String key;
  final http.Client client;
  void close()=>client.close();
  Future<Map> get(String path,Map<String,String> q)async{
    if(key.isEmpty)throw StateError('YouTube Data API 키를 입력하세요.');
    final response=await client.get(Uri.https('www.googleapis.com','/youtube/v3/$path',q),
      headers:{'x-goog-api-key':key}).timeout(const Duration(seconds:25));
    if(response.statusCode!=200)throw StateError('YouTube API HTTP ${response.statusCode} · API 키/권한/할당량을 확인하세요.');
    return jsonDecode(response.body) as Map;
  }
  Future<({List<BenchVideo> top,int scanned,bool complete,String name})> ranking(String id,
    {void Function(int)? progress,int pageLimit=120})async{
    final c=await get('channels',{'part':'contentDetails,snippet','id':id});
    if((c['items'] as List? ?? []).isEmpty)throw StateError('존재하지 않거나 공개되지 않은 채널 ID: $id');
    final channel=(c['items'] as List).first as Map;
    final name=(channel['snippet'] as Map?)?['title'] as String? ?? id;
    final uploads=((channel['contentDetails'] as Map?)?['relatedPlaylists'] as Map?)?['uploads'] as String?;
    if(uploads==null)throw StateError('업로드 재생목록이 없어요.');
    final ids=<String>{};
    String? next;var pages=0;
    do{
      final p=await get('playlistItems',{
        'part':'contentDetails','playlistId':uploads,'maxResults':'50',
        if(next!=null)'pageToken':next});
      for(final item in p['items'] as List? ?? []){
        if(item is Map&&item['contentDetails'] is Map){
          final videoId=(item['contentDetails'] as Map)['videoId'];
          if(videoId is String&&videoId.isNotEmpty)ids.add(videoId);
        }
      }
      next=p['nextPageToken'] as String?;
      pages++;progress?.call(pages);
    }while(next!=null&&pages<pageLimit);
    final list=ids.toList(),videos=<BenchVideo>[];
    for(var i=0;i<list.length;i+=50){
      final p=await get('videos',{'part':'snippet,statistics,contentDetails','id':list.skip(i).take(50).join(',')});
      for(final row in p['items'] as List? ?? []){
        if(row is! Map)continue;
        final meta=row['snippet'],stats=row['statistics'],details=row['contentDetails'];
        if(row['id'] is! String||meta is! Map||stats is! Map||details is! Map)continue;
        final duration=BenchVideo.seconds(details['duration'] as String? ?? '');
        if(duration<1||duration>180)continue; // Shorts candidate, NOT proof of Shorts classification.
        videos.add(BenchVideo(row['id'] as String,id,name,meta['title'] as String? ?? '',
          meta['description'] as String? ?? '',
          int.tryParse(stats['viewCount']?.toString()??'')??0,duration,
          meta['publishedAt'] as String? ?? ''));
      }
    }
    videos.sort((a,b)=>b.views.compareTo(a.views));
    return(top:videos.take(50).toList(),scanned:ids.length,complete:next==null,name:name);
  }
}
).hasMatch(k)){
          final safe=normalOrigin(v);
          if(safe!=null)b.confirmed[k]=safe;
        }
      });
    }
    if(raw['rejected'] is Map){
      (raw['rejected'] as Map).forEach((key,value){
        if(key is! String||value is! List) return;
        final valid=value.whereType<String>().map(normalOrigin).whereType<String>().toSet();
        if(valid.isNotEmpty)b.rejected[key]=valid;
      });
    }
    if(raw['diagnostics'] is Map){
      (raw['diagnostics'] as Map).forEach((k,v){
        if(k is String&&v is String)b.diagnostics[k]=v;
      });
    }
    return b;
  }
  List<BenchVideo> get picked=>[for(final id in selected)for(final list in top.values)for(final v in list)if(v.id==id)v];
  void draw(){
    selected.clear();final rng=Random.secure();
    for(final key in channels.keys){
      final available=(top[key]??[]).where((v)=>!seen.contains(v.id)).toList();
      if(available.isEmpty)continue;
      final v=available[rng.nextInt(available.length)];
      selected.add(v.id);seen.add(v.id);
    }
  }
}
class BenchApi {
  BenchApi(this.key,{http.Client? client}):client=client??http.Client();
  final String key;
  final http.Client client;
  void close()=>client.close();
  Future<Map> get(String path,Map<String,String> q)async{
    if(key.isEmpty)throw StateError('YouTube Data API 키를 입력하세요.');
    final response=await client.get(Uri.https('www.googleapis.com','/youtube/v3/$path',q),
      headers:{'x-goog-api-key':key}).timeout(const Duration(seconds:25));
    if(response.statusCode!=200)throw StateError('YouTube API HTTP ${response.statusCode} · API 키/권한/할당량을 확인하세요.');
    return jsonDecode(response.body) as Map;
  }
  Future<({List<BenchVideo> top,int scanned,bool complete,String name})> ranking(String id,
    {void Function(int)? progress,int pageLimit=120})async{
    final c=await get('channels',{'part':'contentDetails,snippet','id':id});
    if((c['items'] as List? ?? []).isEmpty)throw StateError('존재하지 않거나 공개되지 않은 채널 ID: $id');
    final channel=(c['items'] as List).first as Map;
    final name=(channel['snippet'] as Map?)?['title'] as String? ?? id;
    final uploads=((channel['contentDetails'] as Map?)?['relatedPlaylists'] as Map?)?['uploads'] as String?;
    if(uploads==null)throw StateError('업로드 재생목록이 없어요.');
    final ids=<String>{};
    String? next;var pages=0;
    do{
      final p=await get('playlistItems',{
        'part':'contentDetails','playlistId':uploads,'maxResults':'50',
        if(next!=null)'pageToken':next});
      for(final item in p['items'] as List? ?? []){
        if(item is Map&&item['contentDetails'] is Map){
          final videoId=(item['contentDetails'] as Map)['videoId'];
          if(videoId is String&&videoId.isNotEmpty)ids.add(videoId);
        }
      }
      next=p['nextPageToken'] as String?;
      pages++;progress?.call(pages);
    }while(next!=null&&pages<pageLimit);
    final list=ids.toList(),videos=<BenchVideo>[];
    for(var i=0;i<list.length;i+=50){
      final p=await get('videos',{'part':'snippet,statistics,contentDetails','id':list.skip(i).take(50).join(',')});
      for(final row in p['items'] as List? ?? []){
        if(row is! Map)continue;
        final meta=row['snippet'],stats=row['statistics'],details=row['contentDetails'];
        if(row['id'] is! String||meta is! Map||stats is! Map||details is! Map)continue;
        final duration=BenchVideo.seconds(details['duration'] as String? ?? '');
        if(duration<1||duration>180)continue; // Shorts candidate, NOT proof of Shorts classification.
        videos.add(BenchVideo(row['id'] as String,id,name,meta['title'] as String? ?? '',
          meta['description'] as String? ?? '',
          int.tryParse(stats['viewCount']?.toString()??'')??0,duration,
          meta['publishedAt'] as String? ?? ''));
      }
    }
    videos.sort((a,b)=>b.views.compareTo(a.views));
    return(top:videos.take(50).toList(),scanned:ids.length,complete:next==null,name:name);
  }
}
