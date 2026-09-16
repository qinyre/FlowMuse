import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';

/// 识别期源账本（spec §6.4）：不变量、覆盖率、单向降级、投影与
/// 转换准入七条件。
void main() {
  group('账本不变量', () {
    test('注册即全量 pending；重复 id 拒绝', () {
      final ledger = SourceLedger.register(const ['s1', 's2', 's3']);
      expect(ledger.sourceIds, {'s1', 's2', 's3'});
      expect(ledger.pendingCount, 3);
      expect(
        () => SourceLedger.register(const ['s1', 's1']),
        throwsArgumentError,
      );
    });

    test('consume 的 unit 必须已登记', () {
      final ledger = SourceLedger.register(const ['s1']);
      expect(() => ledger.consume('s1', 'ink:r:s1'), throwsStateError);
      final registered = ledger.registerUnits(const ['ink:r:s1']);
      final consumed = registered.consume('s1', 'ink:r:s1');
      expect(consumed.consumedCount, 1);
      expect(consumed.entryOf('s1').unitId, 'ink:r:s1');
    });

    test('未知源与重复终结拒绝', () {
      final ledger = SourceLedger.register(const [
        's1',
      ]).registerUnits(const ['u1']);
      expect(() => ledger.consume('nope', 'u1'), throwsStateError);
      final consumed = ledger.consume('s1', 'u1');
      expect(() => consumed.consume('s1', 'u1'), throwsStateError);
      expect(
        () => consumed.preserve('s1', SourcePreserveReason.unreadable),
        throwsStateError,
      );
    });

    test('assertAllSettled：未结算抛错，全结算通过', () {
      var ledger = SourceLedger.register(const ['s1', 's2']);
      expect(ledger.assertAllSettled, throwsStateError);
      ledger = ledger.preserve('s1', SourcePreserveReason.nonText);
      expect(ledger.assertAllSettled, throwsStateError);
      ledger = ledger.preserve('s2', SourcePreserveReason.locked);
      ledger.assertAllSettled();
    });
  });

  group('单向降级与投影', () {
    test('consume→preserve 自动降级合法；preserve 终态不可变更', () {
      var ledger = SourceLedger.register(const [
        's1',
      ]).registerUnits(const ['u1']);
      ledger = ledger.consume('s1', 'u1');
      ledger = ledger.downgradeToPreserved(
        's1',
        SourcePreserveReason.budgetExceeded,
      );
      expect(ledger.entryOf('s1').status, SourceLedgerStatus.preserved);
      expect(ledger.entryOf('s1').reason, SourcePreserveReason.budgetExceeded);
      expect(
        () =>
            ledger.downgradeToPreserved('s1', SourcePreserveReason.unreadable),
        throwsStateError,
        reason: '保留终态不可变更',
      );
      // 禁止 preserve→consume 反向升级（无该 API；consume 只接受 pending）。
      expect(() => ledger.consume('s1', 'u1'), throwsStateError);
    });

    test('投影：consumedBy/preservedReasons 只读导出，覆盖率单调', () {
      var ledger = SourceLedger.register(const [
        's1',
        's2',
        's3',
      ]).registerUnits(const ['u1']);
      expect(ledger.projection.coverage, closeTo(0.0, 1e-9));
      expect(ledger.projection.fullySettled, isFalse);
      ledger = ledger
          .consume('s1', 'u1')
          .consume('s2', 'u1')
          .preserve('s3', SourcePreserveReason.missingResponse);
      final projection = ledger.projection;
      expect(projection.fullySettled, isTrue);
      expect(projection.coverage, 1.0);
      expect(projection.consumedBy, {'s1': 'u1', 's2': 'u1'});
      expect(projection.preservedReasons, {
        's3': SourcePreserveReason.missingResponse,
      });
      expect(projection.sourceIds, {'s1', 's2', 's3'});
      expect(
        () => projection.consumedBy['s9'] = 'u9',
        throwsUnsupportedError,
        reason: '投影必须只读',
      );
    });
  });

  group('转换准入七条件（§6.4）', () {
    const guards = {
      's1': SourceGuardFacts(
        isReplaceableInk: true,
        isLocked: false,
        hasCrossBinding: false,
      ),
    };

    Map<String, Object> passArgs() => {
      'statusConfirmedRecognized': true,
      'text': '识别正文',
      'unitSourceIds': const {'s1'},
      'regionTargetSourceIds': const {'s1'},
      'sourceGuards': guards,
      'conflictsResolved': true,
      'versionValid': true,
    };

    test('全条件通过返回 null', () {
      expect(
        ConversionAdmission.check(
          statusConfirmedRecognized: true,
          text: '识别正文',
          unitSourceIds: const {'s1'},
          regionTargetSourceIds: const {'s1'},
          sourceGuards: guards,
          conflictsResolved: true,
          versionValid: true,
        ),
        isNull,
      );
    });

    test('逐条件失败返回对应枚举', () {
      ConversionAdmissionFailure? failureOf({
        bool? statusConfirmedRecognized,
        String? text,
        Set<String>? unitSourceIds,
        Map<String, SourceGuardFacts>? sourceGuards,
        bool? conflictsResolved,
        bool? versionValid,
      }) {
        return ConversionAdmission.check(
          statusConfirmedRecognized: statusConfirmedRecognized ?? true,
          text: text ?? '识别正文',
          unitSourceIds: unitSourceIds ?? const {'s1'},
          regionTargetSourceIds: const {'s1'},
          sourceGuards: sourceGuards ?? guards,
          conflictsResolved: conflictsResolved ?? true,
          versionValid: versionValid ?? true,
        );
      }

      expect(
        failureOf(statusConfirmedRecognized: false),
        ConversionAdmissionFailure.notRecognized,
        reason: '条件1：status 非 recognized（或被复核推翻）',
      );
      expect(
        failureOf(text: '  。！？  '),
        ConversionAdmissionFailure.emptyOrPunctuationText,
        reason: '条件2：纯标点',
      );
      expect(
        failureOf(unitSourceIds: const {'s1', 's2'}),
        ConversionAdmissionFailure.coverageIncomplete,
        reason: '条件3：unit 消费越界（≠区域 target 全集）',
      );
      expect(
        failureOf(
          sourceGuards: const {
            's1': SourceGuardFacts(
              isReplaceableInk: false,
              isLocked: false,
              hasCrossBinding: false,
            ),
          },
        ),
        ConversionAdmissionFailure.sourceTypeForbidden,
        reason: '条件4：非 FreeDraw 或高亮笔刷',
      );
      expect(
        failureOf(
          sourceGuards: const {
            's1': SourceGuardFacts(
              isReplaceableInk: true,
              isLocked: true,
              hasCrossBinding: false,
            ),
          },
        ),
        ConversionAdmissionFailure.protectedSource,
        reason: '条件5：锁定',
      );
      expect(
        failureOf(conflictsResolved: false),
        ConversionAdmissionFailure.unresolvedConflict,
        reason: '条件6：复核冲突未消解',
      );
      expect(
        failureOf(versionValid: false),
        ConversionAdmissionFailure.versionInvalid,
        reason: '条件7：版本四元组/指纹不匹配',
      );
      expect(passArgs().length, 7, reason: '参数与七条件一一对应');
    });

    test('isMeaningfulText：空白/纯标点拒绝，含实义字符通过', () {
      expect(ConversionAdmission.isMeaningfulText(''), isFalse);
      expect(ConversionAdmission.isMeaningfulText('   '), isFalse);
      expect(ConversionAdmission.isMeaningfulText('。，！；'), isFalse);
      expect(ConversionAdmission.isMeaningfulText('.!?'), isFalse);
      expect(ConversionAdmission.isMeaningfulText('·—…×÷'), isFalse);
      expect(ConversionAdmission.isMeaningfulText('abc'), isTrue);
      expect(ConversionAdmission.isMeaningfulText(' 3.14 '), isTrue);
      expect(ConversionAdmission.isMeaningfulText('。好'), isTrue);
    });
  });

  group('保留原因枚举与识别状态协作', () {
    test('reason 有限枚举 wire 名稳定（§3.5/§6.4 不收自由文本）', () {
      const expected = [
        'locked',
        'binding',
        'unreadable',
        'nonText',
        'userKept',
        'budgetExceeded',
        'assetFailed',
        'missingResponse',
        'contextOnly',
      ];
      expect(
        SourcePreserveReason.values.map((reason) => reason.wireName),
        expected,
      );
    });

    test('missingResponse 语义：missingRegionIds 区域按保留处理（§3.2）', () {
      var ledger = SourceLedger.register(const [
        's1',
      ]).registerUnits(const ['u1']);
      ledger = ledger.preserve('s1', SourcePreserveReason.missingResponse);
      final projection = ledger.projection;
      expect(
        projection.preservedReasons['s1'],
        SourcePreserveReason.missingResponse,
      );
      expect(projection.consumedBy, isEmpty);
    });
  });

  test('RecognitionRegionStatus 识别状态与账本 reason 不混淆', () {
    // 模型侧 nonText/unreadable → 账本 reason 同名映射（§6.4 条件 1/6）。
    const statusByReason = {
      SourcePreserveReason.nonText: RecognitionRegionStatus.nonText,
      SourcePreserveReason.unreadable: RecognitionRegionStatus.unreadable,
    };
    for (final entry in statusByReason.entries) {
      expect(entry.key.wireName, entry.value.wireName);
    }
  });
}
