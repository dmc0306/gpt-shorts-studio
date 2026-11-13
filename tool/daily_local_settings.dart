import 'package:flutter/material.dart';
import 'bridge.dart';

/// OS-managed local daily reminder. Does not pretend to execute the UI-bound
/// Flutter video engine automatically after the process is terminated.
class DailyLocalSettingsScreen extends StatefulWidget {
  const DailyLocalSettingsScreen({super.key});
  @override State<DailyLocalSettingsScreen> createState()=>_DailyLocalSettingsScreenState();
}

class _DailyLocalSettingsScreenState extends State<DailyLocalSettingsScreen>{
  bool enabled=false,loading=true,saving=false,rights=false;
  int hour=9,minute=0;
  final creatorText=TextEditingController();
  String last='',result='',message='';

  @override void initState(){
    super.initState();
    _load();
  }

  Future<void> _load()async{
    try{
      final data=await Native.call<Map<dynamic,dynamic>>('dailyScheduleStatus')??{};
      if(!mounted)return;
      setState((){
        enabled=data['enabled']==true;
        hour=(data['hour'] as num?)?.toInt()??9;
        minute=(data['minute'] as num?)?.toInt()??0;
        last=data['lastNoticeDate'] as String? ?? '';
        result=data['lastResult'] as String? ?? '';
        creatorText.text=data['creators'] as String? ?? '';
        rights=data['rightsAttested']==true;
        loading=false;
      });
    }catch(e){if(mounted)setState(()=>loading=false);}
  }

  @override void dispose(){
    creatorText.dispose();
    super.dispose();
  }

  Future<void> _save(bool nextEnabled,int h,int m)async{
    if(saving)return;
    setState(()=>saving=true);
    try{
      if(nextEnabled){
        if(!rights||creatorText.text.trim().isEmpty){
          throw StateError('재게시 허가된 제작자 계정과 권리 확인이 필요합니다.');
        }
        final ok=await Native.call<bool>('batchNotifications');
        if(ok!=true)throw StateError('알림 권한이 필요합니다.');
      }
      final data=await Native.call<Map<dynamic,dynamic>>('dailyScheduleConfigure',{
        'enabled':nextEnabled,'hour':h,'minute':m,
        'creators':creatorText.text.trim(),'rights':rights,
      })??{};
      if(!mounted)return;
      setState((){
        enabled=data['enabled']==true;
        hour=(data['hour'] as num?)?.toInt()??h;
        minute=(data['minute'] as num?)?.toInt()??m;
        last=data['lastNoticeDate'] as String? ?? '';
        result=data['lastResult'] as String? ?? '';
        message=enabled?'매일 예약 알림이 설정됐어요.':'예약 알림을 껐어요.';
      });
    }catch(e){
      if(mounted)setState(()=>message='예약 설정 실패: $e');
    }finally{if(mounted)setState(()=>saving=false);}
  }

  Future<void> _pickTime()async{
    final picked=await showTimePicker(context:context,
      initialTime:TimeOfDay(hour:hour,minute:minute));
    if(picked==null||!mounted)return;
    await _save(enabled,picked.hour,picked.minute);
  }

  @override Widget build(BuildContext context){
    final twoHour=hour.toString().padLeft(2,'0');
    final twoMin=minute.toString().padLeft(2,'0');
    final colors=Theme.of(context).colorScheme;
    return Scaffold(
      appBar:AppBar(title:const Text('기기 백그라운드 예약')),
      body:loading?const Center(child:CircularProgressIndicator()):
        ListView(padding:const EdgeInsets.all(18),children:[
          Card(child:Padding(padding:const EdgeInsets.all(18),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('매일 $twoHour:$twoMin',
                style:Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height:6),
              const Text('한국 시간 · Android WorkManager'),
              SwitchListTile.adaptive(
                contentPadding:EdgeInsets.zero,
                title:const Text('매일 예약 알림'),
                subtitle:const Text('앱 프로세스가 살아 있으면 자동 제작을 시도하고, '
                    '종료된 상태에서는 실행 알림을 보냅니다.'),
                value:enabled,
                onChanged:saving?null:(v)=>_save(v,hour,minute)),
              OutlinedButton.icon(
                onPressed:saving?null:_pickTime,
                icon:const Icon(Icons.schedule),
                label:const Text('시작 시각 변경')),
              const SizedBox(height:10),
              TextField(controller:creatorText,
                enabled:!saving && !enabled,
                decoration:const InputDecoration(
                  labelText:'재게시 허가된 TikTok 제작자 계정',
                  hintText:'mychannel, partnerchannel',
                  helperText:'@ 없이 쉼표로 구분 · 본인 소유 또는 재사용 허가 계정만',
                  border:OutlineInputBorder())),
              CheckboxListTile(
                contentPadding:EdgeInsets.zero,
                title:const Text('위 계정의 영상 수정·재게시 권한이 있습니다'),
                value:rights,
                onChanged:saving||enabled?null:(v)=>setState(()=>rights=v??false)),
              if(last.isNotEmpty)...[
                const SizedBox(height:8),
                Text('마지막 알림: $last',
                  style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
              ],
              if(result.isNotEmpty)Text('최근 실행 결과: $result',
                style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
            ]))),
          const SizedBox(height:14),
          Card(color:colors.surfaceContainerLow,
            child:Padding(padding:const EdgeInsets.all(16),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Icon(Icons.info_outline,color:colors.primary),
                const SizedBox(width:8),
                const Expanded(child:Text('현재 동작 범위',
                  style:TextStyle(fontWeight:FontWeight.w700)))
              ]),
              const SizedBox(height:8),
              const Text('GitHub Actions 없이 휴대폰에서 실행합니다. '
                '앱 화면을 닫더라도 프로세스가 유지되면 예약 시각에 '
                '영상 검색→기존 자막 검사→Gemini→MP4→YouTube 업로드를 '
                '1회 시도합니다. 완전히 종료되거나 시스템에 의해 프로세스가 '
                '제거되면 자동 제작을 보장할 수 없고 확인 알림을 표시합니다. '
                '유튜브 채널 설정의 MP4 자동 업로드를 먼저 활성화해 주세요.'),
              const SizedBox(height:8),
              const Text('정확한 시각에 실행되지 않을 수 있으며, '
                '절전 모드·강제 종료·통신 제한에서는 알림이 지연되거나 빠질 수 있어요.',
                style:TextStyle(fontSize:12)),
            ]))),
          if(message.isNotEmpty)Padding(
            padding:const EdgeInsets.only(top:14),
            child:Text(message,style:TextStyle(color:colors.primary))),
        ]),
    );
  }
}
