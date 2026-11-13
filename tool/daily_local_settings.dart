import 'package:flutter/material.dart';
import 'bridge.dart';

/// OS-managed local daily reminder. Does not pretend to execute the UI-bound
/// Flutter video engine automatically after the process is terminated.
class DailyLocalSettingsScreen extends StatefulWidget {
  const DailyLocalSettingsScreen({super.key});
  @override State<DailyLocalSettingsScreen> createState()=>_DailyLocalSettingsScreenState();
}

class _DailyLocalSettingsScreenState extends State<DailyLocalSettingsScreen>{
  bool enabled=false,loading=true,saving=false;
  int hour=9,minute=0;
  String last='',message='';

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
        loading=false;
      });
    }catch(e){if(mounted)setState(()=>loading=false);}
  }

  Future<void> _save(bool nextEnabled,int h,int m)async{
    if(saving)return;
    setState(()=>saving=true);
    try{
      if(nextEnabled){
        final ok=await Native.call<bool>('batchNotifications');
        if(ok!=true)throw StateError('알림 권한이 필요합니다.');
      }
      final data=await Native.call<Map<dynamic,dynamic>>('dailyScheduleConfigure',{
        'enabled':nextEnabled,'hour':h,'minute':m,
      })??{};
      if(!mounted)return;
      setState((){
        enabled=data['enabled']==true;
        hour=(data['hour'] as num?)?.toInt()??h;
        minute=(data['minute'] as num?)?.toInt()??m;
        last=data['lastNoticeDate'] as String? ?? '';
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
                subtitle:const Text('휴대폰에서 예약 시각에 작업을 알려줍니다.'),
                value:enabled,
                onChanged:saving?null:(v)=>_save(v,hour,minute)),
              OutlinedButton.icon(
                onPressed:saving?null:_pickTime,
                icon:const Icon(Icons.schedule),
                label:const Text('시작 시각 변경')),
              if(last.isNotEmpty)...[
                const SizedBox(height:8),
                Text('마지막 알림: $last',
                  style:TextStyle(fontSize:12,color:colors.onSurfaceVariant)),
              ]
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
              const Text('이 설정은 휴대폰 자체에서 작동하며 GitHub Actions를 사용하지 않습니다. '
                '하지만 아직 백그라운드에서 새 영상을 자동 검색·제작·업로드하지는 않습니다. '
                '예약 시각에는 알림이 도착하고, 알림을 눌러 앱에서 '
                '「혼합 영상 자동 제작」을 실행해야 합니다.'),
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
