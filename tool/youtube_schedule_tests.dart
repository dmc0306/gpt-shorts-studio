import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shorts_studio/youtube_channel.dart';
import 'package:shorts_studio/youtube_publish_plan.dart';
import 'package:shorts_studio/youtube_upload.dart';

void main(){
  test('Public upload metadata is public and private default is safe',(){
    expect(const YouTubePublishPlan.private().status(
      madeForKids:false,syntheticMedia:false)['privacyStatus'],'private');
    final status=const YouTubePublishPlan.public().status(
      madeForKids:false,syntheticMedia:true);
    expect(status['privacyStatus'],'public');
    expect(status.containsKey('publishAt'),false);
    expect(status['containsSyntheticMedia'],true);
  });

  test('Reserved public publication uses private + UTC publishAt',(){
    final future=DateTime.utc(2027,1,20,2,30);
    final status=YouTubePublishPlan.scheduled(future).status(
      madeForKids:false,syntheticMedia:false);
    expect(status['privacyStatus'],'private');
    expect(DateTime.parse(status['publishAt'] as String),future);
  });

  test('Daily/weekly schedule respects clock, one hour lead, old reservation',(){
    final now=DateTime(2026,11,5,8,20);
    final next=YouTubeCadence.nextUtc(now:now,intervalHours:24,
      hour:18,minute:0).toLocal();
    expect(next,DateTime(2026,11,5,18));
    final later=YouTubeCadence.nextUtc(now:now,intervalHours:24,
      hour:18,minute:0,previousUtc:next.toUtc()).toLocal();
    expect(later,DateTime(2026,11,6,18));
    final weekly=YouTubeCadence.previews(now:now,intervalHours:168,
      hour:18,minute:15,count:3).map((e)=>e.toLocal()).toList();
    expect(weekly[1].difference(weekly[0]),const Duration(days:7));
    expect(weekly[2].difference(weekly[1]),const Duration(days:7));
    final tooClose=YouTubeCadence.nextUtc(now:DateTime(2026,11,5,17,30),
      intervalHours:24,hour:18,minute:0).toLocal();
    expect(tooClose,DateTime(2026,11,6,18));
  });

  test('Legacy settings stay private; public auto upload requires same-channel consent',(){
    const channelId='UCaaaaaaaaaaaaaaaaaaaaaa';
    final old=YouTubePreferences.fromJson({
      'email':'me@example.com','channelId':channelId,
      'madeForKids':false,'automatic':true,
    });
    expect(old.publishMode,'private');
    expect(old.automatic,true);

    final unsafe=YouTubePreferences.fromJson({
      'email':'me@example.com','channelId':channelId,
      'madeForKids':false,'automatic':true,'publishMode':'public',
    });
    expect(unsafe.publicApproved,false);
    expect(unsafe.automatic,false);

    final safe=YouTubePreferences.fromJson({
      'email':'me@example.com','channelId':channelId,
      'madeForKids':false,'automatic':true,'publishMode':'scheduled',
      'publicConsentChannel':channelId,'cadenceHours':48,'publishHour':9,
    });
    expect(safe.publicApproved,true);
    expect(safe.automatic,true);
    expect(safe.toJson()['cadenceHours'],48);
    safe.channelId='UCbbbbbbbbbbbbbbbbbbbbbb';
    expect(safe.publicApproved,false);
  });

  test('Resumable uploader sends public status only with explicit plan',()async{
    final folder=Directory.systemTemp.createTempSync('yt-public-test');
    addTearDown(()=>folder.deleteSync(recursive:true));
    final file=File('${folder.path}/source.mp4')..writeAsBytesSync([0,1,2,3,4,5]);
    final state=<String,dynamic>{};
    late Map<String,dynamic> metadata;
    final client=MockClient((request)async{
      if(request.method=='POST'){
        metadata=jsonDecode(request.body) as Map<String,dynamic>;
        return http.Response('',200,headers:{
          'location':'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=test'
        });
      }
      if(request.method=='PUT'){
        return http.Response(jsonEncode({
          'id':'ABCDEFG1234','status':{'privacyStatus':'public'}
        }),201);
      }
      return http.Response('',400);
    });
    final uploader=YouTubeUpload(client:client,token:()async=>'test-token',
      readState:()async=>Map<String,dynamic>.from(state),
      writeState:(map)async{state..clear()..addAll(map);});
    final id=await uploader.upload(file:file,
      email:'me@example.com',channelId:'UCaaaaaaaaaaaaaaaaaaaaaa',
      title:'Original video',description:'Authorized upload',
      madeForKids:false,syntheticMedia:false,
      publishPlan:const YouTubePublishPlan.public(),
      onProgress:(_){});
    expect(id,'ABCDEFG1234');
    expect((metadata['status'] as Map)['privacyStatus'],'public');
    expect((metadata['status'] as Map).containsKey('publishAt'),false);
    expect(state['publishMode'],'public');
    expect(state['actualPrivacy'],'public');
    await uploader.upload(file:file,
      email:'me@example.com',channelId:'UCaaaaaaaaaaaaaaaaaaaaaa',
      title:'Original video',description:'authorized',
      madeForKids:false,syntheticMedia:false,
      publishPlan:const YouTubePublishPlan.private(),
      onProgress:(_){});
    expect(state['publishMode'],'public',
      reason:'Uploaded videos must never silently change privacy on retries');
    client.close();
  });
}
