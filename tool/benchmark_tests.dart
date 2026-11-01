import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shorts_studio/benchmark_data.dart';
import 'package:shorts_studio/vision_reverse.dart';
import 'package:shorts_studio/benchmark_stream.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(){
 test('Video length parser and Shorts candidate bounds',(){
   expect(BenchVideo.seconds('PT1M42S'),102);
   expect(BenchVideo.seconds('PT3M'),180);
   expect(BenchVideo.seconds('PT4M'),240);
   expect(BenchVideo.seconds('P1DT2H3M4S'),93784);
 });
 test('Origin URLs reject profile links and non HTTPS',(){
   expect(normalOrigin('https://www.tiktok.com/@alice/video/12345'),
     'https://www.tiktok.com/@alice/video/12345');
   expect(normalOrigin('https://www.instagram.com/reel/AbC123/'),isNotNull);
   expect(normalOrigin('https://youtube.com/shorts/Abcdefgh1'),isNotNull);
   expect(normalOrigin('https://youtube.com/@profile'),isNull);
   expect(normalOrigin('http://evil.example/video'),isNull);
   expect(normalOrigin('https://tiktok.com.evil.com/@x/video/123'),isNull);
 });
 test('One channel: paged upload playlist, video stats and top-50 sort',()async{
   final log=<String>[];
   final client=MockClient((request)async{
     log.add(request.url.path);
     expect(request.headers['x-goog-api-key'],'test-key');
     final p=request.url.path;
     if(p.endsWith('/channels'))return http.Response(jsonEncode({'items':[{'snippet':{'title':'Test'},
       'contentDetails':{'relatedPlaylists':{'uploads':'UUtest'}}}]}),200);
     if(p.endsWith('/playlistItems')){
       if(!request.url.queryParameters.containsKey('pageToken'))return http.Response(jsonEncode({
         'items':[{'contentDetails':{'videoId':'id1'}},{'contentDetails':{'videoId':'id2'}}],'nextPageToken':'page2'}),200);
       return http.Response(jsonEncode({'items':[{'contentDetails':{'videoId':'id3'}}]}),200);
     }
     if(p.endsWith('/videos'))return http.Response(jsonEncode({'items':[
       {'id':'id1','snippet':{'title':'Low','publishedAt':'2026-01-01','description':'a'},
          'contentDetails':{'duration':'PT25S'},'statistics':{'viewCount':'10'}},
       {'id':'id2','snippet':{'title':'Long','publishedAt':'2026-01-01','description':'b'},
          'contentDetails':{'duration':'PT5M'},'statistics':{'viewCount':'999'}},
       {'id':'id3','snippet':{'title':'Top','publishedAt':'2026-01-01','description':'c'},
          'contentDetails':{'duration':'PT40S'},'statistics':{'viewCount':'9999'}}]}),200);
     throw StateError('unexpected path: $p');
   });
   final service=BenchApi('test-key',client:client);
   final result=await service.ranking('UCtest');
   expect(result.complete,true);expect(result.scanned,3);
   expect(result.top.map((x)=>x.id).toList(),['id3','id1']);
   expect(log.where((x)=>x.endsWith('/playlistItems')).length,2);
   service.close();
 });
 test('Page cap marks ranking incomplete instead of claiming global top 50',()async{
   final c=MockClient((request)async{
     if(request.url.path.endsWith('/channels'))return http.Response(jsonEncode({'items':[{
       'snippet':{'title':'Test'},'contentDetails':{'relatedPlaylists':{'uploads':'UUtest'}}}]}),200);
     if(request.url.path.endsWith('/playlistItems'))return http.Response(jsonEncode({
       'items':[{'contentDetails':{'videoId':'id1'}}],'nextPageToken':'more'}),200);
     return http.Response(jsonEncode({'items':[{'id':'id1','snippet':{'title':'X'},
       'contentDetails':{'duration':'PT30S'},'statistics':{'viewCount':'1'}}]}),200);
   });
   final b=BenchApi('key',client:c);
   expect((await b.ranking('UCtest',pageLimit:1)).complete,false);
   b.close();
 });
 test('Random draws avoid previously selected IDs across channels',(){
   final s=BenchState();
   s.channels.clear();
   s.channels['a']='one';s.channels['b']='two';
   s.top['a']=[const BenchVideo('v1','a','one','x','',10,25,'')];
   s.top['b']=[const BenchVideo('v2','b','two','x','',20,25,'')];
   s.draw();expect(s.selected.toSet(),{'v1','v2'});
   s.draw();expect(s.selected,isEmpty);
   final restored=BenchState.fromJson(s.toJson());
   expect(restored.seen,containsAll(['v1','v2']));
 });


 test('Unrelated pages and repeats in only two frames must be rejected',(){
   final results=FrameReverseSearch.rank([
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.youtube.com/watch?v=Abcdefgh123','score':999},
       {'url':'https://www.tiktok.com/@other/video/123456',
        'fullMatchingImages':[{'url':'https://cdn.example.com/one.jpg'}]}]}},
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.tiktok.com/@other/video/123456',
        'partialMatchingImages':[{'url':'https://cdn.example.com/two.jpg'}]}]}}
   ],'N3b8Zx4Qe5M');
   expect(results,isEmpty);
 });
 test('Cross-verified pages need 3 frame moments including 1 exact match',(){
   const original='https://www.tiktok.com/@original/video/123456';
   const noise='https://www.instagram.com/reel/XyZ123/';
   final matches=FrameReverseSearch.rank([
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':original,'fullMatchingImages':[{'url':'https://cdn.example.com/f1.jpg'}]},
       {'url':noise,'partialMatchingImages':[{'url':'https://cdn.example.com/n1.jpg'}]}]}},
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':original,'partialMatchingImages':[{'url':'https://cdn.example.com/f2.jpg'}]},
       {'url':noise,'partialMatchingImages':[{'url':'https://cdn.example.com/n2.jpg'}]}]}},
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':original,'partialMatchingImages':[{'url':'https://cdn.example.com/f3.jpg'}]},
       {'url':noise,'partialMatchingImages':[{'url':'https://cdn.example.com/n3.jpg'}]}]}}
   ],'N3b8Zx4Qe5M');
   expect(matches.length,1);
   expect(matches.single.url,original);
   expect(matches.single.evidence,contains('3개 시점'));
   expect(matches.single.evidence,contains('완전 일치 1'));
 });
 test('Reference video does not reappear as its own original match',(){
   final hits=FrameReverseSearch.rank([
     for(var i=0;i<3;i++)
       {'webDetection':{'pagesWithMatchingImages':[
          {'url':'https://www.youtube.com/watch?v=N3b8Zx4Qe5M',
           'fullMatchingImages':[{'url':'https://cdn.example.com/frame$i.jpg'}]}]}}
   ],'N3b8Zx4Qe5M');
   expect(hits,isEmpty);
 });
 test('Vision sends images only, not titles or Tavily queries',()async{
   final client=MockClient((request)async{
     expect(request.url.host,'vision.googleapis.com');
     expect(request.url.queryParameters['key'],'vision-key');
     final data=jsonDecode(request.body) as Map;
     expect(data.keys.toList(),['requests']);
     final requests=data['requests'] as List;
     expect(requests.length,3);
     expect(jsonEncode(requests),contains('WEB_DETECTION'));
     expect(jsonEncode(requests),isNot(contains('Tavily')));
     return http.Response(jsonEncode({'responses':[
       for(var i=0;i<3;i++)
         {'webDetection':{'pagesWithMatchingImages':[
           {'url':'https://www.youtube.com/shorts/AbCdEfGhijk',
            if(i==0)'fullMatchingImages':[{'url':'https://cdn.example.com/img$i.jpg'}],
            if(i!=0)'partialMatchingImages':[{'url':'https://cdn.example.com/img$i.jpg'}]}]}}
     ]}),200);
   });
   final engine=FrameReverseSearch('vision-key',client:client);
   final results=await engine.find('reference',[
     for(var i=0;i<3;i){'content':List.filled(150,'A').join()}
   ]);
   expect(results.single.evidence,contains('3개 시점'));
   engine.close();
 });

 test('YouTube video-only stream rejects unsupported manifest safely',(){
   expect(()=>BenchmarkStreamResolver.choose(<VideoOnlyStreamInfo>[]),
     throwsA(isA<BenchmarkStreamError>()));
 });
 test('Video-only stream size cap prevents oversized temporary cache',(){
   expect(BenchmarkStreamResolver.maxBytes,lessThan(100*1024*1024));
 });
}
