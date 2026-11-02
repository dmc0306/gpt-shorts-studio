import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shorts_studio/benchmark_data.dart';
import 'package:shorts_studio/vision_reverse.dart';
import 'package:shorts_studio/benchmark_stream.dart';
import 'package:shorts_studio/benchmark_oneclick.dart';
import 'package:shorts_studio/benchmark_duration.dart';
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

 test('YouTube video-only stream rejects unsupported manifest safely',(){
   expect(()=>BenchmarkStreamResolver.choose(<VideoOnlyStreamInfo>[]),
     throwsA(isA<BenchmarkStreamError>()));
 });
 test('Video-only stream size cap prevents oversized temporary cache',(){
   expect(BenchmarkStreamResolver.maxBytes,lessThan(100*1024*1024));
 });
 test('Vision accepts a single direct image match only as an unverified lead',(){
   final suggestions=FrameReverseSearch.discoveryCandidates([
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.tiktok.com/@creator/video/123456',
        'fullMatchingImages':[{'url':'https://cdn.example.com/abc.jpg'}]},
       {'url':'https://www.youtube.com/watch?v=12345678901'}]}}
   ],'ABCDEFGHIJK');
   expect(suggestions.length,2);
   expect(suggestions.first.source,'이미지 직접일치 후보');
   expect(suggestions.first.evidence,contains('직접 이미지 일치 근거'));
   expect(suggestions.last.source,'연관 페이지만 확인');
 });
 test('Visual verification requires distinct matching reference and candidate scenes',(){
   final reference=[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':38},
     {'hash':'5555555555555555','contrast':52},
   ];
   final candidate=[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':38},
     {'hash':'5555555555555555','contrast':52},
     {'hash':'0000000000000000','contrast':53},
   ];
   final verified=VideoMatch.match(reference,candidate);
   expect(verified.matched,2);
   expect(verified.distinctCandidate,2);
   expect(verified.best,0);
   expect(VideoMatch.strong(verified),true);
   final single=VideoMatch.match(reference,[candidate.first]);
   expect(VideoMatch.strong(single),false);
 });
 test('Scene similarity alone does not prove an original with inserted captions',(){
   final overlay=<String,dynamic>{'lines':[
     for(final t in [1,2,3,4])
       {'x':.12,'y':.81,'w':.56,'letters':7,'time':t,'watermark':false}
   ]};
   expect(OverlayCheck.suspicious(overlay),true);
   expect(OverlayCheck.suspicious({'lines':[
     {'x':.2,'y':.43,'w':.3,'letters':6,'time':1},
   ]}),false);
   expect(OverlayCheck.suspicious({}),true);
 });
 test('YouTube original candidate links are strictly video IDs',(){
   expect(OneClickExplorer.youtubeId('https://www.youtube.com/shorts/AbcDefGhI12'),'AbcDefGhI12');
   expect(OneClickExplorer.youtubeId('https://www.youtube.com/@anyone'),null);
 });

 test('Search diagnostics distinguish no web image index from unsupported video page',(){
   const none=VisionSearchReport(candidates:[],frames:6,pages:0,
      pagesWithEvidence:0,socialPosts:0,indexedImages:0);
   expect(none.diagnostic,contains('웹페이지가 0개'));
   const notIndexed=VisionSearchReport(candidates:[],frames:6,pages:13,
      pagesWithEvidence:2,socialPosts:0,indexedImages:4);
   expect(notIndexed.diagnostic,contains('개별 게시물 0건'));
   const several=VisionSearchReport(candidates:[],frames:6,pages:25,
      pagesWithEvidence:4,socialPosts:3,indexedImages:9);
   expect(several.diagnostic,contains('소셜 게시물 단서 3건'));
 });
 test('Per-video search diagnostic text survives cache restore',(){
   final state=BenchState();
   state.diagnostics['abc123']='웹 이미지 일치 페이지 0건';
   final restored=BenchState.fromJson(state.toJson());
   expect(restored.diagnostics['abc123'],state.diagnostics['abc123']);
 });

 test('Thumbnail fallback is image-only evidence, never sufficient for video confirmation',(){
   final reference=[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':25},
     {'hash':'5555555555555555','contrast':36}
   ];
   expect(CandidateThumbnail.closest(reference,'aaaaaaaaaaaaaaaa'),0);
   expect(CandidateThumbnail.closest(reference,'FFFFFFFFFFFFFFFF'),greaterThan(0));
   expect(VideoMatch.strong(VideoMatch.match(reference,[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':35}
   ])),false);
 });

 test('Provider failure diagnostics avoid presenting raw TikTok HTML and remain concise',(){
   final detail=CandidateFailure.describe(StateError('PAGE_UNAVAILABLE TikTok video api JSON 10204 '
     '${List.filled(100,'html payload').join()}'));
   expect(detail,contains('10204'));
   expect(detail,isNot(contains('html payload')));
   final denied=CandidateFailure.describe(StateError('HTTP 403 Forbidden'));
   expect(denied,contains('403'));
   final huge=CandidateFailure.describe(StateError(List.filled(400,'x').join()));
   expect(huge.length,lessThan(220));
 });

 test('ISO8601 YouTube durations and video length thresholds are bounded',(){
   expect(BenchmarkDuration.iso8601('PT42S'),42);
   expect(BenchmarkDuration.iso8601('PT1M10S'),70);
   expect(BenchmarkDuration.iso8601('PT2H1M3S'),7263);
   expect(BenchmarkDuration.iso8601('not-a-duration'),null);
   expect(BenchmarkDuration.tolerance(42),9);
   expect(BenchmarkDuration.similar(42,51),true);
   expect(BenchmarkDuration.similar(42,52),false);
   expect(BenchmarkDuration.similar(8,5),true);
   expect(BenchmarkDuration.similar(8,4),false);
   expect(BenchmarkDuration.label(42,null),contains('확인 불가'));
   expect(BenchmarkDuration.label(42,60),contains('길이 불일치'));
 });
 test('Multiple OCR crops from one candidate time do not fake distinct scenes',(){
   final reference=[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':42},
     {'hash':'5555555555555555','contrast':42},
   ];
   final sameFrame=[
     {'hash':'aaaaaaaaaaaaaaaa','contrast':44,'timeMs':2000},
     {'hash':'5555555555555555','contrast':44,'timeMs':2000},
   ];
   final m=VideoMatch.match(reference,sameFrame);
   expect(m.matched,2);
   expect(m.distinctCandidate,1);
   expect(VideoMatch.strong(m),false);
 });

 test('User-known Shorts to TikTok source pair is preserved independent of image search',(){
   const id='NPom9sHH2J0';
   const userLink='https://vt.tiktok.com/ZSp11jbJd/';
   expect(benchmarkGroundTruth[id],userLink);
   final state=BenchState();
   expect(state.confirmed[id],userLink);
   state.origins[id]=[const BenchOrigin('https://www.youtube.com/watch?v=AAAAAAAAAAA',
       '역검색에서 발견한 관련 페이지','역이미지 탐색 후보')];
   final restored=BenchState.fromJson(state.toJson());
   expect(restored.confirmed[id],userLink);
   expect(restored.origins[id]!.single.source,'역이미지 탐색 후보');
 });
 test('TikTok vt and vm short links are accepted without allowing other hosts',(){
   expect(normalOrigin('https://vt.tiktok.com/ZSp11jbJd/'),
     'https://vt.tiktok.com/ZSp11jbJd/');
   expect(normalOrigin('https://vt.tiktok.com/ZSp11jbJd/?share=abc'),
     'https://vt.tiktok.com/ZSp11jbJd/');
   expect(normalOrigin('https://vm.tiktok.com/Ab1CdE2/'),
     'https://vm.tiktok.com/Ab1CdE2/');
   expect(normalOrigin('https://vt.tiktok.com.evil.example/ZSp11jbJd/'),isNull);
   expect(normalOrigin('http://vt.tiktok.com/ZSp11jbJd/'),isNull);
   expect(normalOrigin('https://vt.tiktok.com/'),isNull);
 });

 test('Direct frame-image matches rank ahead of unrelated high-score social pages',(){
   final raw=[
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.instagram.com/reel/strongA/',
        'fullMatchingImages':[{'url':'https://img.example/1.jpg'}]},
       {'url':'https://www.youtube.com/watch?v=weakweak123','score':99999},
       {'url':'https://www.tiktok.com/@user/video/123456',
        'partialMatchingImages':[{'url':'https://img.example/2.jpg'}]}
     ]}},
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.instagram.com/reel/strongA/',
        'partialMatchingImages':[{'url':'https://img.example/3.jpg'}]},
       {'url':'https://www.instagram.com/reel/weak123/'}
     ]}},
   ];
   final sorted=FrameReverseSearch.discoveryCandidates(raw,'AbcDefGhI12');
   expect(sorted[0].url,'https://www.instagram.com/reel/strongA/');
   expect(sorted[0].source,'이미지 직접일치 후보');
   expect(sorted[1].source,'이미지 직접일치 후보');
   expect(sorted.where((p)=>p.source=='연관 페이지만 확인').length,2);
   expect(sorted.last.source,'연관 페이지만 확인');
 });
 test('Page-only leads are capped to 3 and never treated as direct matches',(){
   final list=FrameReverseSearch.discoveryCandidates([
     {'webDetection':{'pagesWithMatchingImages':[
       for(var i=0;i<12;i++)
         {'url':'https://www.instagram.com/reel/p$i/'}
     ]}}
   ],'AbcDefGhI12');
   expect(list.length,3);
   expect(list.every((e)=>e.source=='연관 페이지만 확인'),true);
 });
 test('Rejected links persist per benchmark and can be cleared',(){
   final state=BenchState();
   state.rejected['AbcDefGhI12']={
     'https://www.youtube.com/watch?v=12345678901',
     'https://www.instagram.com/reel/bad123/',
   };
   final recovered=BenchState.fromJson(state.toJson());
   expect(recovered.rejected['AbcDefGhI12']!.length,2);
   expect(recovered.rejected['OtherVid012'],isNull);
   recovered.rejected.remove('AbcDefGhI12');
   expect(recovered.rejected.isEmpty,true);
 });

}
