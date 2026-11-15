/// UI wording is derived only from verified YouTube receipt counts.
/// Merely finishing the for-loop is not proof that anything was uploaded.
String youtubeBatchOutcomeMessage({
  required int succeeded,
  required int failed,
  required int unattempted,
  bool cancelled=false,
}) {
  if(succeeded<0||failed<0||unattempted<0){
    throw ArgumentError('영상 수는 음수일 수 없습니다.');
  }
  if(cancelled){
    return '전송 중단 · YouTube 영상 ID 확인 $succeeded개 · '
      '실패 $failed개 · 미전송 $unattempted개. '
      '확인되지 않은 영상은 게시 완료로 표시하지 않습니다.';
  }
  if(failed>0){
    return '업로드 실패 $failed개 · YouTube 접수 확인 $succeeded개 · '
      '미전송 $unattempted개. '
      'YouTube 예약은 접수가 확인된 영상에만 등록됐을 수 있습니다. '
      '실패한 영상과 남은 영상은 기기에 유지됩니다.';
  }
  if(succeeded>0&&unattempted==0){
    return 'YouTube 영상 ID 확인 $succeeded개 · 전송 접수 완료. '
      '실제 게시/처리 상태는 YouTube Studio에서 확인해 주세요.';
  }
  return '업로드 확인 0개 · 미전송 $unattempted개. '
    '공개 예약이 등록되지 않았습니다.';
}
