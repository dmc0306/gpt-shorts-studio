import 'dart:convert';
import 'package:http/http.dart' as http;
import 'youtube_upload.dart';

/// Authoritative owner-only YouTube schedule lookup. Unknown is NOT empty.
/// Ordinary private or unlisted videos without publishAt do not count.
class YouTubeScheduledQueue {
  YouTubeScheduledQueue(this.client,this.token,this.channelId);
  final http.Client client;
  final String token,channelId;
  static const maxPages=20;

  Never _unknown()=>throw const YouTubeFailure(
    '예약 목록을 완전히 확인하지 못했어요. 중복 방지를 위해 자동 제작을 보류합니다. [YT_QUEUE_UNKNOWN]');

  Future<Map> _get(String path,Map<String,String> params)async{
    final response=await client.get(
      Uri.https('www.googleapis.com','/youtube/v3/$path',params),
      headers:{'Authorization':'Bearer $token'},
    ).timeout(const Duration(seconds:30));
    YouTubeUpload.check(response);
    final value=jsonDecode(response.body);
    if(value is! Map||value['items'] is! List)_unknown();
    return value;
  }

  static bool isScheduled(Map status,DateTime now){
    final publishAt=status['publishAt'];
    if(status['privacyStatus']!='private'||publishAt is! String)return false;
    final parsed=DateTime.tryParse(publishAt);
    if(parsed==null)throw const YouTubeFailure('예약 시간 응답 형식이 올바르지 않아요. [YT_QUEUE_UNKNOWN]');
    return !['deleted','failed','rejected'].contains(status['uploadStatus'])
      &&parsed.isAfter(now.toUtc());
  }

  Future<bool> hasScheduled(DateTime now)async{
    final owned=await _get('channels',{'part':'contentDetails','mine':'true','maxResults':'50'});
    final channels=owned['items'] as List;
    if(channels.length!=1||owned['nextPageToken']!=null||
       channels.first is! Map||channels.first['id']!=channelId)_unknown();
    final content=channels.first['contentDetails'];
    final playlists=content is Map?content['relatedPlaylists']:null;
    final uploads=playlists is Map?playlists['uploads']:null;
    if(uploads is! String||uploads.isEmpty)_unknown();
    String? page;
    final pages=<String>{};
    for(var i=0;i<maxPages;i++){
      final data=await _get('playlistItems',{
        'part':'contentDetails','playlistId':uploads,'maxResults':'50',
        if(page!=null)'pageToken':page,
      });
      final ids=<String>{};
      for(final item in data['items'] as List){
        final detail=item is Map?item['contentDetails']:null;
        final id=detail is Map?detail['videoId']:null;
        if(id is! String||id.isEmpty)_unknown();
        ids.add(id);
      }
      if(ids.isNotEmpty){
        final videos=await _get('videos',{'part':'status,snippet','id':ids.join(',')});
        final received=<String>{};
        for(final item in videos['items'] as List){
          if(item is! Map||item['id'] is! String||!ids.contains(item['id'])||
              item['snippet'] is! Map||item['snippet']['channelId']!=channelId||
              item['status'] is! Map)_unknown();
          received.add(item['id'] as String);
          final status=item['status'] as Map;
          // A private video with an overdue publishAt may still be processing;
          // defer rather than presume its reservation disappeared.
          if(isScheduled(status,now)||
              (status['privacyStatus']=='private'&&status['publishAt']!=null&&
               !['failed','deleted','rejected'].contains(status['uploadStatus'])))return true;
        }
        if(received.length!=ids.length)_unknown();
      }
      final next=data['nextPageToken'];
      if(next==null)return false;
      if(next is! String||next.isEmpty||!pages.add(next))_unknown();
      page=next;
    }
    _unknown();
  }

  /// Verify each new upload is visible on the exact channel and really scheduled.
  Future<bool> verifyScheduled(String id,DateTime now)async{
    final data=await _get('videos',{'part':'status,snippet','id':id});
    final items=data['items'] as List;
    if(items.length!=1||items.first is! Map||items.first['id']!=id||
       items.first['snippet'] is! Map||items.first['snippet']['channelId']!=channelId||
       items.first['status'] is! Map)_unknown();
    return isScheduled(items.first['status'] as Map,now);
  }
}
