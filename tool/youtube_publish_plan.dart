/// YouTube release schedule calculation. Publication is executed by YouTube
/// after a private upload with status.publishAt. A running Android service is
/// not required once YouTube accepted the scheduled upload.
class YouTubePublishPlan {
  const YouTubePublishPlan.private() : privacyStatus='private', publishAt=null;
  const YouTubePublishPlan.public() : privacyStatus='public', publishAt=null;
  const YouTubePublishPlan.scheduled(DateTime when)
      : privacyStatus='private', publishAt=when;
  final String privacyStatus;
  final DateTime? publishAt;

  String get mode=>publishAt!=null?'scheduled':privacyStatus;
  Map<String,dynamic> status({
    required bool madeForKids,required bool syntheticMedia,
  }){
    if(privacyStatus!='private'&&privacyStatus!='public'){
      throw const FormatException('공개 범위를 확인해 주세요.');
    }
    final when=publishAt;
    if(when!=null&&privacyStatus!='private'){
      throw const FormatException('예약 게시 영상은 비공개로 업로드해야 해요.');
    }
    return {
      'privacyStatus':privacyStatus,
      if(when!=null)'publishAt':when.toUtc().toIso8601String(),
      'selfDeclaredMadeForKids':madeForKids,
      'containsSyntheticMedia':syntheticMedia,
    };
  }
}

class YouTubeCadence {
  static const supportedHours=[24,48,72,168];

  static DateTime nextUtc({
    required DateTime now,
    required int intervalHours,
    required int hour,
    required int minute,
    DateTime? previousUtc,
  }){
    if(!supportedHours.contains(intervalHours)||hour<0||hour>23||
       minute<0||minute>59){
      throw const FormatException('유효한 업로드 주기와 시간을 선택해 주세요.');
    }
    // At least one hour of lead time avoids accidental publication
    // while the video is still uploading or processing.
    final earliest=now.add(const Duration(hours:1));
    var date=DateTime(now.year,now.month,now.day,hour,minute);
    var attempts=0;
    while(!date.isAfter(earliest)||
          (previousUtc!=null&&!date.toUtc().isAfter(previousUtc))){
      date=date.add(Duration(hours:intervalHours));
      if(++attempts>100000){
        throw const FormatException('예약 날짜를 계산할 수 없어요.');
      }
    }
    return date.toUtc();
  }

  static List<DateTime> previews({
    required DateTime now,
    required int intervalHours,
    required int hour,
    required int minute,
    DateTime? previousUtc,
    required int count,
  }){
    if(count<0||count>100)throw const FormatException('예약 건수는 0~100개만 허용해요.');
    final result=<DateTime>[];
    var previous=previousUtc;
    for(var i=0;i<count;i++){
      final slot=nextUtc(now:now,intervalHours:intervalHours,
        hour:hour,minute:minute,previousUtc:previous);
      result.add(slot);
      previous=slot;
    }
    return result;
  }

  static String label(int intervalHours)=>switch(intervalHours){
    24=>'매일',48=>'2일마다',72=>'3일마다',168=>'매주',
    _=>'사용자 지정',
  };
}
