import 'package:flutter/material.dart';
import 'model.dart';
import 'youtube.dart';
import 'youtube_channel.dart';
import 'youtube_publish_plan.dart';

/// Uploads finished MP4s while this screen remains active, creating YouTube
/// server-side publishAt schedules. No claim of offline/background uploading.
class YouTubeBatchPublishScreen extends StatefulWidget {
  const YouTubeBatchPublishScreen({super.key,required this.clips});
  final List<Clip> clips;
  @override State<YouTubeBatchPublishScreen> createState()=>_YouTubeBatchPublishState();
}

class _YouTubeBatchPublishState extends State<YouTubeBatchPublishScreen>{
  final youtube=YouTube.instance;
  final picked=<String>{};
  final results=<String,String>{};
  final uploaded=<String>{};
  bool loading=true,running=false,cancelRequested=false;
  String message='';
  String? active;

  List<Clip> get finished=>widget.clips.where((c)=>c.savedUri.isNotEmpty)
    .toList(growable:false);

  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    try{
      await youtube.loadSettings();
      for(final c in finished){
        final state=await youtube.state(c.savedUri);
        if(state['videoId'] is String)uploaded.add(c.id);
      }
    }catch(e){message=youtubeError(e);}
    if(mounted)setState(()=>loading=false);
  }

  String modeLabel(YouTubePreferences p)=>switch(p.publishMode){
    'public'=>'즉시 전체 공개','scheduled'=>'주기별 공개 예약',
    _=>'비공개',
  };
  List<DateTime> _slots(int count){
    final p=youtube.preferences;
    final last=DateTime.tryParse(p.lastScheduledAtUtc);
    return YouTubeCadence.previews(now:DateTime.now(),
      intervalHours:p.cadenceHours,hour:p.publishHour,minute:p.publishMinute,
      previousUtc:last,count:count);
  }
  String _date(DateTime value){
    final t=value.toLocal();
    String two(int n)=>n.toString().padLeft(2,'0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _uploadBatch()async{
    if(running||loading||picked.isEmpty||youtube.uploading)return;
    final p=youtube.preferences;
    if(!p.confirmed||(p.publishMode!='private'&&!p.publicApproved)){
      setState(()=>message='업로드 채널과 공개 권한을 유튜브 설정에서 먼저 확인해 주세요.');
      return;
    }
    final items=finished.where((c)=>picked.contains(c.id)&&!uploaded.contains(c.id))
      .take(20).toList();
    if(items.isEmpty)return;
    final dates=p.publishMode=='scheduled'?_slots(items.length):<DateTime>[];
    final allowed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('선택한 영상을 유튜브에 올릴까요?'),
      content:SingleChildScrollView(child:Text(
        '채널: ${p.channelTitle}\n'
        '영상: ${items.length}개\n'
        '공개 방식: ${modeLabel(p)}\n'
        '${dates.isNotEmpty?'첫 게시 ${_date(dates.first)} / 마지막 게시 ${_date(dates.last)}\n':''}'
        '\n선택 영상은 지금부터 순서대로 전송됩니다. '
        '전송된 예약 영상은 앱을 종료해도 YouTube가 설정된 시간에 공개합니다. '
        '전송이 끝나기 전에 앱을 닫으면 남은 영상은 업로드되지 않습니다.\n\n'
        '직접 제작했거나 게시·재이용 권한이 있는 영상만 업로드해야 합니다. '
        '저작권, 원제작자, 자막 여부를 확인해 주세요.'
      )),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('취소')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),
          child:Text(p.publishMode=='scheduled'?'공개 예약 시작':'업로드 시작'))
      ],
    ));
    if(allowed!=true||!mounted)return;
    setState((){
      running=true;
      cancelRequested=false;
      results.clear();
      message='전송 시작';
    });
    for(final item in items){
      if(cancelRequested)break;
      if(!mounted)break;
      setState((){
        active=item.id;
        message='전송 중: ${item.headline.isEmpty?item.name:item.headline}';
      });
      try{
        final id=await youtube.uploadClip(item);
        if(!mounted)break;
        setState((){
          uploaded.add(item.id);
          picked.remove(item.id);
          results[item.id]='전송 접수 · https://www.youtube.com/watch?v=$id';
        });
      }catch(e){
        if(!mounted)break;
        setState((){
          results[item.id]='업로드 실패 · ${youtubeError(e)}';
          message='중단됨 · 실패한 영상과 남은 영상은 앱에 유지돼요.';
        });
        break; // Avoid flooding quota and disturbing order on failure.
      }
    }
    if(!mounted)return;
    setState((){
      active=null;
      running=false;
      message=cancelRequested?'전송 중단 · 남은 영상은 그대로 유지돼요.':
        '선택한 영상의 전송 시도를 마쳤어요. 공개/처리 상태는 YouTube Studio에서도 확인해 주세요.';
    });
  }

  void _cancel(){
    if(!running)return;
    setState((){
      cancelRequested=true;
      message='현재 영상 전송을 중단하고 남은 업로드도 시작하지 않습니다.';
    });
    youtube.cancelUpload();
  }

  @override Widget build(BuildContext context){
    final p=youtube.preferences;
    final available=finished.where((c)=>!uploaded.contains(c.id)).toList();
    final items=available.where((c)=>picked.contains(c.id)).toList();
    final slots=p.publishMode=='scheduled'?_slots(items.length):<DateTime>[];
    final colors=Theme.of(context).colorScheme;
    return Scaffold(
      appBar:AppBar(title:const Text('유튜브 공개·예약 업로드')),
      body:loading?const Center(child:CircularProgressIndicator()):
        ListView(padding:const EdgeInsets.all(16),children:[
          Card(child:Padding(padding:const EdgeInsets.all(16),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(p.channelTitle.isNotEmpty?p.channelTitle:'업로드 채널을 먼저 연결해 주세요.',
                style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:5),
              Text('공개 방식: ${modeLabel(p)}',
                style:TextStyle(color:colors.onSurfaceVariant)),
              if(p.publishMode=='scheduled')
                Text('${YouTubeCadence.label(p.cadenceHours)} '
                  '${p.publishHour.toString().padLeft(2,'0')}:'
                  '${p.publishMinute.toString().padLeft(2,'0')} (휴대폰 현지시간)'),
              const SizedBox(height:8),
              const Text('선택된 MP4를 지금 유튜브에 업로드하고 '
                '예약 게시일은 유튜브에 등록합니다. '
                '남은 파일을 앱이 꺼진 상태에서 새로 업로드하지는 않습니다.',
                style:TextStyle(fontSize:12)),
            ]))),
          const SizedBox(height:14),
          Row(children:[
            Expanded(child:Text('저장된 영상 ${available.length}개',
              style:Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed:running?null:()=>setState((){
              if(items.length==available.length){picked.clear();}
              else{picked..clear()..addAll(available.take(20).map((c)=>c.id));}
            }),child:Text(items.length==available.length?'모두 해제':'최대 20개 선택'))
          ]),
          for(final item in available)
            CheckboxListTile(
              value:picked.contains(item.id),
              onChanged:running?null:(checked)=>setState((){
                if(checked==true){
                  if(picked.length<20)picked.add(item.id);
                }else{picked.remove(item.id);}
              }),
              title:Text(item.headline.isNotEmpty?item.headline:item.name,
                maxLines:2,overflow:TextOverflow.ellipsis),
              subtitle:Text(results[item.id]??'완성 MP4 · ${item.duration.toStringAsFixed(0)}초',
                maxLines:2,overflow:TextOverflow.ellipsis),
              controlAffinity:ListTileControlAffinity.leading,
            ),
          if(uploaded.isNotEmpty)
            ExpansionTile(title:Text('업로드 완료 또는 기존 전송 ${uploaded.length}개'),
              children:[
                for(final clip in finished.where((c)=>uploaded.contains(c.id)))
                  ListTile(dense:true,title:Text(clip.headline.isEmpty?clip.name:clip.headline),
                    subtitle:Text(results[clip.id]??'기존 전송 · 재업로드하지 않음'))
              ]),
          if(items.isNotEmpty&&p.publishMode=='scheduled')...[
            const Divider(height:26),
            const Text('게시 예정 시간',style:TextStyle(fontWeight:FontWeight.bold)),
            for(var i=0;i<slots.length;i++)
              Padding(padding:const EdgeInsets.symmetric(vertical:3),
                child:Text('${i+1}. ${_date(slots[i])} · '
                  '${items[i].headline.isEmpty?items[i].name:items[i].headline}',
                  maxLines:1,overflow:TextOverflow.ellipsis)),
          ],
          const SizedBox(height:12),
          if(running)LinearProgressIndicator(value:youtube.progress),
          if(message.isNotEmpty)Padding(
            padding:const EdgeInsets.symmetric(vertical:8),child:Text(message)),
          FilledButton.icon(
            onPressed:running||picked.isEmpty||youtube.uploading?null:_uploadBatch,
            icon:const Icon(Icons.cloud_upload_outlined),
            label:Text(p.publishMode=='scheduled'
              ?'선택 ${items.length}개 지금 업로드하고 공개 예약'
              :'선택 ${items.length}개 ${modeLabel(p)} 업로드')),
          if(running)
            OutlinedButton(onPressed:_cancel,child:const Text('전송 중단 · 남은 영상 유지')),
          const SizedBox(height:12),
          const Text('이미 유튜브에 업로드한 MP4는 중복 업로드하지 않습니다. '
            '과거에 비공개로 업로드한 영상의 공개 범위 변경은 YouTube Studio에서 확인해 주세요.',
            style:TextStyle(fontSize:12)),
        ]),
    );
  }
}
