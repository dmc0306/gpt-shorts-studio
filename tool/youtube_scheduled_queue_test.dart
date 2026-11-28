import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shorts_studio/youtube_scheduled_queue.dart';
import 'package:shorts_studio/youtube_upload.dart';

const channel='UC1234567890123456789012';
final now=DateTime.utc(2026,11,28,0);
http.Response json(Map body)=>http.Response(jsonEncode(body),200);
Map video(String id,Map status)=>{'id':id,'snippet':{'channelId':channel},'status':status};
Map playlist(String id)=>{'contentDetails':{'videoId':id}};
Map owned()=>{'items':[{'id':channel,'contentDetails':{'relatedPlaylists':{'uploads':'UU123'}}}]};

void main(){
  test('future private publishAt counts; ordinary private does not',(){
    expect(YouTubeScheduledQueue.isScheduled({'privacyStatus':'private','publishAt':'2026-11-28T12:00:00Z'},now),true);
    expect(YouTubeScheduledQueue.isScheduled({'privacyStatus':'private'},now),false);
    expect(YouTubeScheduledQueue.isScheduled({'privacyStatus':'public','publishAt':'2026-11-28T12:00:00Z'},now),false);
    expect(YouTubeScheduledQueue.isScheduled({'privacyStatus':'private','publishAt':'2026-11-28T12:00:00Z','uploadStatus':'rejected'},now),false);
  });
  test('lookup follows next page and stops if future reservation exists',()async{
    final paths=<String>[];
    final client=MockClient((r)async{
      expect(r.headers['Authorization'],'Bearer test');
      paths.add(r.url.path);
      if(r.url.path.endsWith('/channels'))return json(owned());
      if(r.url.path.endsWith('/playlistItems')){
        if(r.url.queryParameters['pageToken']==null)return json({'items':[playlist('a')],'nextPageToken':'p2'});
        return json({'items':[playlist('b')]});
      }
      final id=r.url.queryParameters['id']!;
      return json({'items':[video(id,{'privacyStatus':id=='a'?'public':'private',
        if(id=='b')'publishAt':'2026-11-29T00:00:00Z'})]});
    });
    expect(await YouTubeScheduledQueue(client,'test',channel).hasScheduled(now),true);
    expect(paths.length,5);
  });
  test('completely empty uploads playlist is confirmed empty',()async{
    final client=MockClient((r)async=>r.url.path.endsWith('/channels')
      ?json(owned()):json({'items':[]}));
    expect(await YouTubeScheduledQueue(client,'test',channel).hasScheduled(now),false);
  });
  test('missing video response is unknown, never empty',()async{
    final client=MockClient((r)async{
      if(r.url.path.endsWith('/channels'))return json(owned());
      if(r.url.path.endsWith('/playlistItems'))return json({'items':[playlist('a')]});
      return json({'items':[]});
    });
    await expectLater(YouTubeScheduledQueue(client,'test',channel).hasScheduled(now),throwsA(isA<YouTubeFailure>()));
  });
  test('HTTP failure and mismatched channel fail closed',()async{
    for(final response in [http.Response('{}',503),json({'items':[{'id':'other'}]})]){
      final client=MockClient((r)async=>response);
      await expectLater(YouTubeScheduledQueue(client,'test',channel).hasScheduled(now),throwsA(isA<YouTubeFailure>()));
    }
  });
  test('new upload must really be scheduled, not merely private',()async{
    final client=MockClient((r)async=>json({'items':[video('a',{'privacyStatus':'private'})]}));
    expect(await YouTubeScheduledQueue(client,'test',channel).verifyScheduled('a',now),false);
  });
  test('only an actually public overdue upload can settle pending state',()async{
    final client=MockClient((r)async=>json({'items':[video('a',{'privacyStatus':'public'})]}));
    final reader=YouTubeScheduledQueue(client,'test',channel);
    expect(await reader.verifyPublished('a',now,DateTime.utc(2026,11,27)),true);
    expect(await reader.verifyPublished('a',now,DateTime.utc(2026,11,29)),false);
    expect(await reader.verifyPublished('a',now,null),false);
    final privateClient=MockClient((r)async=>json({'items':[video('a',{'privacyStatus':'private'})]}));
    expect(await YouTubeScheduledQueue(privateClient,'test',channel)
      .verifyPublished('a',now,DateTime.utc(2026,11,27)),false);
  });
  test('overdue private scheduled video still blocks auto refill conservatively',()async{
    final client=MockClient((r)async{
      if(r.url.path.endsWith('/channels'))return json(owned());
      if(r.url.path.endsWith('/playlistItems'))return json({'items':[playlist('a')]});
      return json({'items':[video('a',{'privacyStatus':'private','publishAt':'2026-11-27T00:00:00Z'})]});
    });
    expect(await YouTubeScheduledQueue(client,'test',channel).hasScheduled(now),true);
  });
}
