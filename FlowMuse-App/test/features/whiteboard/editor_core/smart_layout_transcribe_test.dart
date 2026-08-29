import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 低置信裁剪重问：触发条件、择优采用规则与转写协议模型。
/// 触发（shouldReAskTranscription）：无文本或把握 < 0.7 才重问；
/// 择优（adoptTranscription）：新结果有文字且把握严格更高才采用——与原文
/// 不同采用新文；与原文相同则采信原文并把把握提升到新值（两次独立读一致，
/// 清除存疑橙框）。
void main() {
  group('SmartLayoutTranscribeRequest 模型', () {
    test('toJson：hint 为空时不下发，避免锚定模型', () {
      const withHint = SmartLayoutTranscribeRequest(
        imageBase64: 'aGk=',
        hint: '我的笔记',
      );
      expect(withHint.toJson()['hint'], '我的笔记');
      expect(withHint.toJson()['imageMime'], 'image/png');

      const withoutHint = SmartLayoutTranscribeRequest(imageBase64: 'aGk=');
      expect(withoutHint.toJson().containsKey('hint'), isFalse);
    });
  });

  group('SmartLayoutTranscribeResponse 模型', () {
    test('fromJson：去首尾空白、confidence 钳制到 0-1', () {
      final response = SmartLayoutTranscribeResponse.fromJson({
        'text': '  先头小子  ',
        'confidence': 1.5,
      });
      expect(response.text, '先头小子');
      expect(response.confidence, 1);

      final empty = SmartLayoutTranscribeResponse.fromJson({
        'text': '   ',
        'confidence': 0.8,
      });
      expect(empty.text, isEmpty);
    });
  });

  group('裁剪重问触发条件', () {
    test('无文本（VLM 未给出转写）触发重问', () {
      expect(
        MarkdrawController.shouldReAskTranscription(text: null, confidence: 0.9),
        isTrue,
      );
      expect(
        MarkdrawController.shouldReAskTranscription(text: '   ', confidence: 0.9),
        isTrue,
      );
    });

    test('把握低于阈值 0.7 触发重问，达到阈值不重问', () {
      expect(
        MarkdrawController.shouldReAskTranscription(text: '字', confidence: 0.55),
        isTrue,
      );
      expect(
        MarkdrawController.shouldReAskTranscription(text: '字', confidence: 0.7),
        isFalse,
      );
      expect(
        MarkdrawController.shouldReAskTranscription(text: '字', confidence: 0.95),
        isFalse,
      );
    });
  });

  group('裁剪重问择优规则', () {
    test('重问失败（null）或无文字 → 保留原结果', () {
      expect(
        MarkdrawController.adoptTranscription(
          currentText: 'M',
          currentConfidence: 0.4,
          reAsk: null,
        ),
        isNull,
      );
      expect(
        MarkdrawController.adoptTranscription(
          currentText: 'M',
          currentConfidence: 0.4,
          reAsk: const SmartLayoutTranscribeResponse(text: '', confidence: 0),
        ),
        isNull,
      );
    });

    test('新结果与原文相同且把握更高 → 采信原文并提升把握（清除存疑橙框）', () {
      final adopted = MarkdrawController.adoptTranscription(
        currentText: '总结',
        currentConfidence: 0.55,
        reAsk: const SmartLayoutTranscribeResponse(
          text: '总结',
          confidence: 0.95,
        ),
      );
      expect(adopted, isNotNull, reason: '两次独立读一致应清除存疑状态');
      expect(adopted!.text, '总结');
      expect(adopted.confidence, 0.95);
    });

    test('新结果与原文相同但把握不升 → 保留原结果', () {
      expect(
        MarkdrawController.adoptTranscription(
          currentText: '总结',
          currentConfidence: 0.95,
          reAsk: const SmartLayoutTranscribeResponse(
            text: '总结',
            confidence: 0.6,
          ),
        ),
        isNull,
      );
    });

    test('新结果与原文不同且把握不升 → 不采用', () {
      expect(
        MarkdrawController.adoptTranscription(
          currentText: '总结',
          currentConfidence: 0.75,
          reAsk: const SmartLayoutTranscribeResponse(
            text: '结总',
            confidence: 0.7,
          ),
        ),
        isNull,
      );
    });

    test('新结果有文字且把握更高 → 采用（"M"→"先"场景）', () {
      final adopted = MarkdrawController.adoptTranscription(
        currentText: 'M',
        currentConfidence: 0.4,
        reAsk: const SmartLayoutTranscribeResponse(
          text: '先',
          confidence: 0.85,
        ),
      );
      expect(adopted, isNotNull);
      expect(adopted!.text, '先');
      expect(adopted.confidence, 0.85);
    });

    test('原文本为空（红区块）时任意有文字的高把握结果都采用', () {
      final adopted = MarkdrawController.adoptTranscription(
        currentText: '',
        currentConfidence: -1,
        reAsk: const SmartLayoutTranscribeResponse(text: '子', confidence: 0.1),
      );
      expect(adopted, isNotNull);
      expect(adopted!.text, '子');
    });
  });
}
