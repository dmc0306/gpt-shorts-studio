import 'package:flutter_test/flutter_test.dart';
import 'package:shorts_studio/gemini_retry.dart';

void main(){
  test('503 twice then success reuses request and backs off',()async{
    final waits=<int>[],attempts=<int>[];
    final value=await GeminiRetry.run<String>(
      send:(n)async{attempts.add(n);if(n<3)throw 503;return 'OK';},
      is503:(e)=>e==503,safeToReplay:true,check:(){},
      wait:(d)async{waits.add(d.inSeconds);},
    );
    expect(value,'OK');
    expect(attempts,[1,2,3]);expect(waits,[5,10]);
  });
  test('persistent 503 stops after four attempts',()async{
    final waits=<int>[],attempts=<int>[];
    await expectLater(GeminiRetry.run<void>(
      send:(n)async{attempts.add(n);throw 503;},
      is503:(e)=>e==503,safeToReplay:true,check:(){},
      wait:(d)async{waits.add(d.inSeconds);},
    ),throwsA(503));
    expect(attempts,[1,2,3,4]);expect(waits,[5,10,20]);
  });
  test('non503 and uncertain upload never replay',()async{
    for(final code in [429,503]){
      int count=0;
      await expectLater(GeminiRetry.run<void>(
        send:(n)async{count++;throw code;},
        is503:(e)=>e==503,safeToReplay:code!=503,check:(){},
        wait:(d)async{fail('must not retry');},
      ),throwsA(code));
      expect(count,1);
    }
  });
  test('cancel during delay prevents another HTTP request',()async{
    bool stopped=false;int calls=0;
    await expectLater(GeminiRetry.run<void>(
      send:(n)async{calls++;throw 503;},
      is503:(e)=>e==503,safeToReplay:true,
      check:(){if(stopped)throw StateError('cancelled');},
      wait:(d)async{stopped=true;},
    ),throwsStateError);
    expect(calls,1);
  });
  test('diagnostics allowlist avoids raw error text and credentials',(){
    final detail=GeminiRetry.safeServerDetail(
      '{"error":{"status":"UNAVAILABLE","message":"overloaded API key SECRET https://private.example/file"}}');
    expect(detail,contains('UNAVAILABLE'));
    expect(detail,contains('과부하'));
    expect(detail,isNot(contains('SECRET')));
    expect(detail,isNot(contains('https')));
    expect(GeminiRetry.safeModel('gemini-3.5-flash-lite'),'gemini-3.5-flash-lite');
    expect(GeminiRetry.safeModel('https://secret'),' (확인 불가)'.trim());
  });
}
