import 'dart:async';
import 'dart:convert';

/// Only replay requests that can safely be repeated (generation and GET).
/// No retry of a resumable upload finalization with an unknown outcome.
class GeminiRetry {
  static const delays=[
    Duration(seconds:5), Duration(seconds:10), Duration(seconds:20),
  ];

  static Future<T> run<T>({
    required Future<T> Function(int attempt) send,
    required bool Function(Object error) is503,
    required bool safeToReplay,
    required void Function() check,
    required Future<void> Function(Duration delay) wait,
    void Function(int retry, Duration delay)? onRetry,
  }) async {
    for(var attempt=1;;attempt++){
      check();
      try{
        return await send(attempt);
      }catch(error){
        check();
        if(!safeToReplay||!is503(error)||attempt>delays.length)rethrow;
        final delay=delays[attempt-1];
        onRetry?.call(attempt,delay);
        await wait(delay);
        check();
      }
    }
  }

  /// Only show known provider status and a short allowlisted interpretation
  /// of the message. Unknown/free-form server text may contain request data,
  /// URLs, file identifiers, or credentials; do not expose it.
  static String safeServerDetail(String raw){
    const allowed={
      'UNAVAILABLE','INTERNAL','RESOURCE_EXHAUSTED','INVALID_ARGUMENT',
      'PERMISSION_DENIED','UNAUTHENTICATED','NOT_FOUND','DEADLINE_EXCEEDED',
      'FAILED_PRECONDITION','ABORTED','UNKNOWN',
    };
    try{
      final decoded=jsonDecode(raw);
      final error=decoded is Map?decoded['error']:null;
      if(error is! Map)return '서버 오류 설명 없음';
      final value=error['status'];
      final status=value is String&&allowed.contains(value)?value:'';
      final message=error['message'];
      final m=message is String?message.toLowerCase():'';
      final explanation=m.contains('overloaded')||m.contains('high demand')||
          m.contains('capacity')?'모델 과부하 또는 처리 용량 부족':
        m.contains('unavailable')?'서비스 일시 사용 불가':
        m.contains('retry')||m.contains('try again')?'서버에서 재시도 요청':
        m.contains('quota')||m.contains('rate limit')?'요청량 또는 할당량 관련 오류':
        m.contains('deadline')||m.contains('timed out')?'서버 처리 시간 초과':
        '서버 상세 메시지는 개인정보 보호를 위해 생략';
      return status.isEmpty?explanation:'$status · $explanation';
    }catch(_){
      return '서버 오류 설명을 읽지 못했어요.';
    }
  }

  static String safeModel(String model)=>
    RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(model)?model:'(확인 불가)';
}
