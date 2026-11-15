import 'package:flutter_test/flutter_test.dart';
import 'package:shorts_studio/youtube_batch_outcome.dart';

void main(){
  test('An authentication failure never shows a successful batch',(){
    final message=youtubeBatchOutcomeMessage(
      succeeded:0,failed:1,unattempted:4);
    expect(message,contains('업로드 실패 1개'));
    expect(message,contains('접수 확인 0개'));
    expect(message,contains('미전송 4개'));
    expect(message, isNot(contains('전송 접수 완료')));
  });
  test('Only confirmed video IDs count as accepted uploads',(){
    final message=youtubeBatchOutcomeMessage(
      succeeded:2,failed:1,unattempted:2);
    expect(message,contains('접수 확인 2개'));
    expect(message,contains('업로드 실패 1개'));
    expect(message,contains('미전송 2개'));
  });
  test('All five accepted videos can report YouTube receipt',(){
    final message=youtubeBatchOutcomeMessage(
      succeeded:5,failed:0,unattempted:0);
    expect(message,contains('영상 ID 확인 5개'));
    expect(message,contains('전송 접수 완료'));
    expect(message,contains('YouTube Studio'));
  });
  test('Cancelled batch cannot claim complete',(){
    final message=youtubeBatchOutcomeMessage(
      succeeded:1,failed:0,unattempted:4,cancelled:true);
    expect(message,contains('전송 중단'));
    expect(message,isNot(contains('전송 접수 완료')));
  });
  test('Zero uploads is not YouTube-side scheduling',(){
    final message=youtubeBatchOutcomeMessage(
      succeeded:0,failed:0,unattempted:5);
    expect(message,contains('공개 예약이 등록되지 않았습니다'));
  });
  test('Reject negative counters',(){
    expect(()=>youtubeBatchOutcomeMessage(
      succeeded:-1,failed:1,unattempted:0),throwsArgumentError);
  });
}
