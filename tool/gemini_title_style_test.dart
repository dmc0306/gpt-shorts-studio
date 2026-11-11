import 'package:flutter_test/flutter_test.dart';
import 'package:shorts_studio/ai.dart';
import 'package:shorts_studio/ai_rules.dart';
import 'package:shorts_studio/headline.dart';

void main() {
  test('Gemini title prompt uses short natural viral Korean Shorts tone', () {
    expect(titleRules, contains('액체 고양이'));
    expect(titleRules, contains('나도 좀 먹고 살자'));
    expect(titleRules, contains('상위 1%'));
    expect(titleRules, contains('근거'));
    expect(titleRules, contains('호기심형'));
    expect(titleRules, contains('반전형'));
    expect(titleRules, contains('유머형'));
    expect(titleRules, contains('영상에 실제로'));
    expect(titleRules, contains('5~11자'));
    expect(titleRules, contains('공백'));
    expect(titleRules, contains('낱말 중간'));
  });

  test('Viral-style example titles still obey both independent 5-11 constraints', () {
    expect(validHeadline('휴대폰 보다가\n스스로를 찍었다'), true);
    expect(validHeadline('액체가 된 고양이\n몸이 왜 저래?'), true);
    expect(validHeadline('나도 좀 먹고\n살자고 이러냐'), true);
    expect(validHeadline('그네 타다 생긴\n예상 밖의 결말'), true);
    expect(validHeadline('상위 1% 강아지\n대체 뭘 했길래'), true);
    expect(validHeadline('액체 고양이\n짧음'), false);
  });

  test('App rejects every style when one Gemini title is too long', () {
    final titles = {
      'titles': {
        'curiosity': {'top':'휴대폰 보다가','bottom':'스스로를 찍었다'},
        'twist': {'top':'그네 타다 생긴','bottom':'예상 밖의 결말'},
        'humor': {'top':'나도 좀 먹고','bottom':'살자고 이러냐'},
      }
    };
    expect(GeminiCaptions.decodeTitles(titles),hasLength(3));
    (titles['titles'] as Map)['humor']={
      'top':'지나치게 긴 제목을 출력하면 안됨',
      'bottom':'살자고 이러냐',
    };
    expect(()=>GeminiCaptions.decodeTitles(titles),throwsA(isA<AiFailure>()));
  });
}
