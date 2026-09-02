library;

/// V3-506A 事务体验矩阵（Gate 4 证据）：从真实入口
/// （SmartLayoutRealSessionScope + loopback 真实 HTTP）驱动七类事务
/// 场景，对每个场景做 **六态一致性** 快照断言——
/// Scene（fingerprint）/ History（undo/redo 计数）/ revision
/// （tracker fingerprint）/ broadcast（sceneChangeListeners 事件）/
/// document（scene.smartLayout 版本）/ ledger（patch 账本终态）。
///
/// 场景覆盖（原 V3-506A～B 合并）：preview=commit、undo/redo、
/// cancel/late、draft 释放、local/remote conflict（写集相交拒绝 +
/// 不相交重派一次）、纠错重跑、渲染/排名证据（a11y 证据由
/// test/features/whiteboard/smart_layout/views 的
/// V3-505C 键盘/语义/零 modal 用例承载，报告内以指针引用）。

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/commit/validated_candidate_commit_gateway.dart'
    show HistoryCommitted;
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';



/// 六态快照：机器可判定的状态证据。
class TransactionStateSnapshot {
  const TransactionStateSnapshot({
    required this.sceneFingerprint,
    required this.undoCount,
    required this.redoCount,
    required this.revisionFingerprint,
    required this.broadcastEvents,
    required this.documentVersion,
    required this.ledgerConsumed,
    required this.ledgerPreserved,
    required this.ledgerHash,
  });

  final String sceneFingerprint;
  final int undoCount;
  final int redoCount;
  final String revisionFingerprint;
  /// 广播事件（source 序列；协作通道的本地可观测投影）。
  final List<String> broadcastEvents;
  final int? documentVersion;
  final int ledgerConsumed;
  final int ledgerPreserved;
  final String? ledgerHash;

  Map<String, Object?> toJson() => {
    'sceneFingerprint': sceneFingerprint,
    'undoCount': undoCount,
    'redoCount': redoCount,
    'revisionFingerprint': revisionFingerprint,
    'broadcastEvents': broadcastEvents,
    'documentVersion': documentVersion,
    'ledger': {
      'consumed': ledgerConsumed,
      'preserved': ledgerPreserved,
      'hash': ledgerHash,
    },
  };
}

/// 单场景结果。
class TransactionMatrixCase {
  const TransactionMatrixCase({
    required this.id,
    required this.title,
    required this.passed,
    required this.checks,
    required this.before,
    required this.after,
    this.failure,
  });

  final String id;
  final String title;
  final bool passed;
  final List<String> checks;
  final TransactionStateSnapshot? before;
  final TransactionStateSnapshot? after;
  final String? failure;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'passed': passed,
    'checks': checks,
    'failure': failure,
    'before': before?.toJson(),
    'after': after?.toJson(),
  };
}

/// 矩阵报告（gate_four_report 数据面；写入
/// evidence/smart-layout-v3/gates/G4/transaction-matrix-report.json）。
class TransactionMatrixReport {
  const TransactionMatrixReport({
    required this.generatedAtUtc,
    required this.cases,
    required this.a11yEvidencePointers,
  });

  final String generatedAtUtc;
  final List<TransactionMatrixCase> cases;
  final List<String> a11yEvidencePointers;

  bool get allPassed => cases.every((c) => c.passed);

  Map<String, Object?> toJson() => {
    'generatedAtUtc': generatedAtUtc,
    'allPassed': allPassed,
    'caseCount': cases.length,
    'a11yEvidencePointers': a11yEvidencePointers,
    'cases': [for (final c in cases) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// 事务矩阵驱动器（target symbol V3-506A）。
///
/// [handler]：loopback 服务响应（与 V3-505C 集成测试同口径）。
/// 每场景独立 controller/scope/server，互不污染。
abstract final class TransactionMatrixRunner {
  static const pageId = 'page-1';

  /// a11y 证据指针：V3-505C 已提交的可访问性用例（键盘全流程/方向键
  /// 候选/无解分支/liveRegion 播报/零 modal 有界泵收敛）。
  static const a11yPointers = [
    'test/features/whiteboard/smart_layout/views/smart_layout_session_view_test.dart'
        '::V3-505C 无鼠标/可访问性闭环::键盘全流程：Enter 开始 → Escape 取消 → Enter 复位并归还焦点',
    'test/features/whiteboard/smart_layout/views/smart_layout_session_view_test.dart'
        '::V3-505C 无鼠标/可访问性闭环::reviewing 键盘：方向键切换候选、Enter 应用所选',
    'FlowMuse-App/lib/features/whiteboard/smart_layout/views/'
        'smart_layout_session_view.dart'
        '::Semantics(container/liveRegion/button/selected) 全相位覆盖',
  ];

  static Future<TransactionMatrixReport> run({
    required Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String line)? onTrace,
  }) async {
    final trace = onTrace ?? (_) {};
    final cases = <TransactionMatrixCase>[];

    // ---- S1 preview=commit + S2 undo/redo（同一事务生命周期）----
    cases.addAll(await _previewCommitAndUndoRedo(handler, trace));
    // ---- S3 cancel/late ----
    cases.add(await _cancelLate(handler, trace));
    // ---- S4 draft 释放 ----
    cases.add(await _draftRelease(handler, trace));
    // ---- S5 local/remote conflict（相交/不相交）----
    cases.addAll(await _conflict(handler, trace));
    // ---- S6 纠错重跑 ----
    cases.add(await _correctionRerun(handler, trace));
    // ---- S7 渲染/排名证据 ----
    cases.add(await _renderRankingEvidence(handler, trace));

    return TransactionMatrixReport(
      generatedAtUtc: DateTime.now().toUtc().toIso8601String(),
      cases: cases,
      a11yEvidencePointers: a11yPointers,
    );
  }

  // ==================== 场景夹具 ====================

  static const pageCustomData = {
    'flowMuse': {'role': 'page', 'pageId': pageId},
  };
  static const onPageCustomData = {
    'flowMuse': {'pageId': pageId},
  };

  static String regionBody({String role = 'body', String source = 'text-1'}) =>
      jsonEncode({
        'protocolVersion': 3,
        'requestId': 'req-1',
        'regions': [
          {
            'id': 'g1',
            'role': role,
            'sourceIds': [source],
            'readingOrder': 0,
            'confidence': 0.9,
            'relations': <String>[],
          },
        ],
        'warnings': <String>[],
      });

  static RectangleElement canvasPage() => RectangleElement(
    id: const ElementId('page-frame'),
    x: 0,
    y: 0,
    width: 1200,
    height: 800,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    customData: pageCustomData,
  );

  static TextElement pageText() => TextElement(
    id: const ElementId('text-1'),
    x: 200,
    y: 300,
    width: 320,
    height: 40,
    text: '正文内容文本',
    fontSize: 20,
    fontFamily: 'Excalifont',
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    customData: onPageCustomData,
  );

  static RectangleElement pageShape() => RectangleElement(
    id: const ElementId('shape-1'),
    x: 500,
    y: 600,
    width: 60,
    height: 40,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    customData: onPageCustomData,
  );

  // ==================== 六态快照 ====================

  static TransactionStateSnapshot snapshotOf(
    MarkdrawController controller,
    SceneRevisionTracker observer, {
    List<String> broadcast = const [],
    ValidatedCandidate? ledgerOf,
  }) {
    final scene = controller.currentScene;
    return TransactionStateSnapshot(
      sceneFingerprint: SceneFingerprint.of(scene).value,
      undoCount: controller.historyManager.undoCount,
      redoCount: controller.historyManager.redoCount,
      revisionFingerprint: observer.isDisposed ? 'disposed' : observer
          .current
          .fingerprint
          .value,
      broadcastEvents: List.unmodifiable(broadcast),
      documentVersion: scene.smartLayout?.version,
      ledgerConsumed: ledgerOf?.patch.sourceCoverage.consumedCount ?? 0,
      ledgerPreserved: ledgerOf?.patch.sourceCoverage.preservedCount ?? 0,
      ledgerHash: ledgerOf?.ledgerHash,
    );
  }

  /// loopback + 真实 NativeHttpClient 执行体（HttpOverrides 摘除由
  /// 调用方测试负责；本 runner 只在真实网络栈上跑）。
  static Future<T> withLoopback<T>(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    Future<T> Function(Uri serverUri, List<String> bodies) body,
  ) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final bodies = <String>[];
    final sub = server.listen((request) async {
      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk as List<int>);
      }
      bodies.add(utf8.decode(builder.takeBytes()));
      final (status, responseBody) = await handler(request);
      request.response.statusCode = status;
      if (status == 200) {
        request.response.headers.contentType = io.ContentType.json;
        request.response.write(responseBody);
      }
      await request.response.close();
    });
    try {
      return await body(
        Uri.parse('http://127.0.0.1:${server.port}'),
        bodies,
      );
    } finally {
      await sub.cancel();
      await server.close();
    }
  }

  /// 真实作用域 + 广播记录 + 独立 revision 观察器 + VM 容器。
  static MatrixHarness harness(Uri serverUri, {bool withShape = false}) {
    final controller = MarkdrawController();
    controller.applyResult(AddElementResult(canvasPage()));
    controller.applyResult(AddElementResult(pageText()));
    if (withShape) {
      controller.applyResult(AddElementResult(pageShape()));
    }
    final broadcasts = <String>[];
    controller.sceneChangeListeners.add(
      (scene, source) => broadcasts.add(source.name),
    );
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: serverUri,
      pageId: pageId,
      // HTTP 仓库路径口径（生产视觉链由 wiring 视觉闭环组覆盖）。
      useVisionAnalysis: false,
    );
    final observer = SceneRevisionTracker(
      editor: SmartLayoutEditorGateway(controller),
    );
    final container = ProviderContainer(
      overrides: [
        smartLayoutSessionDependenciesProvider.overrideWithValue(
          scope.dependencies,
        ),
      ],
    );
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier)
      ..addScopeSource('text-1');
    return MatrixHarness(
      controller: controller,
      scope: scope,
      observer: observer,
      container: container,
      vm: vm,
      broadcasts: broadcasts,
    );
  }

  // ==================== S1+S2：preview=commit + undo/redo ====================

  static Future<List<TransactionMatrixCase>> _previewCommitAndUndoRedo(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    return withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final checks = <String>[];
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        final state1 = h.container.read(smartLayoutSessionViewModelProvider);
        if (state1.phase != SmartLayoutSessionPhase.reviewing ||
            state1.validatedCards.isEmpty) {
          return [
            TransactionMatrixCase(
              id: 'S1-preview-commit',
              title: 'preview=commit：真实候选提交与归约产物等价',
              passed: false,
              checks: const [],
              before: before,
              after: null,
              failure: '生成链未产出候选：${state1.phase}/'
                  '${state1.failure}',
            ),
          ];
        }
        final candidate = state1.selectedValidatedCandidate!;
        // preview=commit（502A 口径）：负载深度等价——排除 versionNonce/
        // updated（applyResult 提交时重新盖章），version 数字一致，
        // 元素 id 集一致；触达元素逐字段比对。
        final previewFingerprint = SceneFingerprint.of(
          candidate.reduced.scene,
        ).value;
        checks.add('preview fingerprint=$previewFingerprint');

        await h.vm.applySelectedCandidate();
        final state2 = h.container.read(smartLayoutSessionViewModelProvider);
        checks.add('phase applied=${state2.phase == SmartLayoutSessionPhase.applied}');

        final after = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
          ledgerOf: candidate,
        );
        // 六态一致性（preview=commit 负载口径，见上）。
        final committedScene = h.controller.currentScene;
        final payloadEquivalent = _payloadEquivalent(
          candidate.reduced.scene,
          committedScene,
        );
        var ok = state2.phase == SmartLayoutSessionPhase.applied;
        ok &= payloadEquivalent;
        checks.add(
          'scene payload==preview=$payloadEquivalent'
          '(applyResult 盖章 versionNonce/updated，全量 fingerprint 仅记录)',
        );
        ok &= after.undoCount == before.undoCount + 1;
        checks.add('history undo+1=${after.undoCount == before.undoCount + 1}');
        ok &= after.revisionFingerprint == after.sceneFingerprint;
        checks.add('revision==scene=${after.revisionFingerprint == after.sceneFingerprint}');
        ok &= h.broadcasts.isNotEmpty;
        checks.add('broadcast events=${h.broadcasts.length}');
        final op = candidate.patch.documentOp;
        final doc = op?.document;
        final documentOk =
            doc == null
            ? after.documentVersion == before.documentVersion
            : after.documentVersion == doc.version;
        ok &= documentOk;
        checks.add('document consistent=$documentOk'
            '(after=${after.documentVersion}, op=${doc?.version})');
        final ledger = candidate.patch.sourceCoverage;
        ok &= ledger.isFinalized;
        checks.add(
          'ledger finalized=${ledger.isFinalized}'
          '(consumed=${ledger.consumedCount}, preserved=${ledger.preservedCount})',
        );

        final s1 = TransactionMatrixCase(
          id: 'S1-preview-commit',
          title: 'preview=commit：真实候选提交与归约产物等价 + 六态一致',
          passed: ok,
          checks: checks,
          before: before,
          after: after,
          failure: ok ? null : '六态断言存在失败项',
        );

        // ---- S2 undo/redo ----
        final undoChecks = <String>[];
        final committed = after;
        h.controller.undo();
        final undone = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
        );
        var undoOk = undone.sceneFingerprint == before.sceneFingerprint;
        undoOk &= undone.undoCount == committed.undoCount - 1;
        undoOk &= undone.redoCount == committed.redoCount + 1;
        undoChecks.add(
          'undo→pre-commit scene=${undone.sceneFingerprint == before.sceneFingerprint}',
        );
        undoChecks.add(
          'undo history=${undone.undoCount}/${undone.redoCount}',
        );
        h.controller.redo();
        final redone = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
        );
        undoOk &= redone.sceneFingerprint == committed.sceneFingerprint;
        undoOk &= redone.undoCount == committed.undoCount;
        undoChecks.add(
          'redo→committed scene=${redone.sceneFingerprint == committed.sceneFingerprint}',
        );
        final s2 = TransactionMatrixCase(
          id: 'S2-undo-redo',
          title: 'undo/redo：一次 undo 精确回提交前、redo 回提交后',
          passed: undoOk,
          checks: undoChecks,
          before: committed,
          after: redone,
          failure: undoOk ? null : 'undo/redo 断言存在失败项',
        );
        trace('S1=${s1.passed} S2=${s2.passed}');
        return [s1, s2];
      } finally {
        await h.dispose();
      }
    });
  }

  // ==================== S3：cancel/late ====================

  static Future<TransactionMatrixCase> _cancelLate(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    final gate = Completer<void>();
    return withLoopback(
      (request) async {
        await gate.future;
        return handler(request);
      },
      (serverUri, _) async {
        final h = harness(serverUri);
        try {
          final before = snapshotOf(h.controller, h.observer);
          final analysis = h.vm.startAnalysis();
          h.vm.cancel();
          final cancelled = h.container.read(
            smartLayoutSessionViewModelProvider,
          );
          gate.complete();
          await analysis;
          final state = h.container.read(smartLayoutSessionViewModelProvider);
          final after = snapshotOf(
            h.controller,
            h.observer,
            broadcast: h.broadcasts,
          );
          final checks = <String>[
            'cancel sync phase=${cancelled.phase == SmartLayoutSessionPhase.cancelled}',
            'late discarded phase=${state.phase == SmartLayoutSessionPhase.cancelled}',
            'cards empty=${state.validatedCards.isEmpty}',
            'scene unchanged=${after.sceneFingerprint == before.sceneFingerprint}',
            'history 0=${after.undoCount == before.undoCount}',
            'revision unchanged=${after.revisionFingerprint == before.revisionFingerprint}',
            'broadcast none=${h.broadcasts.isEmpty}',
          ];
          final ok =
              state.phase == SmartLayoutSessionPhase.cancelled &&
              state.validatedCards.isEmpty &&
              after.sceneFingerprint == before.sceneFingerprint &&
              after.undoCount == before.undoCount &&
              after.revisionFingerprint == before.revisionFingerprint &&
              h.broadcasts.isEmpty;
          trace(ok ? 'S3=true' : 'S3=false :: ${checks.join(' | ')}');
          return TransactionMatrixCase(
            id: 'S3-cancel-late',
            title: '取消：在途立即终止；迟到响应票据判旧零残留',
            passed: ok,
            checks: checks,
            before: before,
            after: after,
            failure: ok ? null : '取消/迟到断言存在失败项',
          );
        } finally {
          await h.dispose();
          if (!gate.isCompleted) gate.complete();
        }
      },
    );
  }

  // ==================== S4：draft 释放 ====================

  static Future<TransactionMatrixCase> _draftRelease(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    return withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        final state = h.container.read(smartLayoutSessionViewModelProvider);
        final candidate = state.selectedValidatedCandidate;
        if (candidate == null) {
          return TransactionMatrixCase(
            id: 'S4-draft-release',
            title: '候选草稿资源释放：取消即 dispose（零泄漏）',
            passed: false,
            checks: const [],
            before: before,
            after: null,
            failure: '生成链未产出候选',
          );
        }
        final image = candidate.snapshot.image;
        final aliveBefore = !image.debugDisposed;
        h.vm.cancel();
        final after = h.container.read(smartLayoutSessionViewModelProvider);
        final disposedAfter = image.debugDisposed;
        final checks = <String>[
          'thumbnail alive pre-cancel=$aliveBefore',
          'thumbnail disposed post-cancel=$disposedAfter',
          'cards cleared=${after.validatedCards.isEmpty}',
          'scene untouched=${snapshotOf(h.controller, h.observer).sceneFingerprint == before.sceneFingerprint}',
        ];
        final ok = aliveBefore && disposedAfter && after.validatedCards.isEmpty;
        trace(ok ? 'S4=true' : 'S4=false :: ${checks.join(' | ')}');
        return TransactionMatrixCase(
          id: 'S4-draft-release',
          title: '候选草稿资源释放：取消即 dispose（零泄漏）',
          passed: ok,
          checks: checks,
          before: before,
          after: snapshotOf(
            h.controller,
            h.observer,
            broadcast: h.broadcasts,
          ),
          failure: ok ? null : '草稿释放断言存在失败项',
        );
      } finally {
        await h.dispose();
      }
    });
  }

  // ==================== S5：local/remote conflict ====================

  static Future<List<TransactionMatrixCase>> _conflict(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    // ---- 相交：远端改写写集元素 → writeSetConflict 零副作用 ----
    final intersect = await withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        var state = h.container.read(smartLayoutSessionViewModelProvider);
        if (state.validatedCards.isEmpty) {
          return TransactionMatrixCase(
            id: 'S5a-conflict-intersect',
            title: '写集相交：远端改写写集元素 → 拒绝且六态零副作用',
            passed: false,
            checks: const [],
            before: before,
            after: null,
            failure: '生成链未产出候选',
          );
        }
        // 远端改写 text-1（版本前进；模拟远端编辑落地）。
        h.controller.applyResult(
          UpdateElementResult(
            pageText().copyWith(x: 260, version: 99),
          ),
        );
        final afterRemote = h.controller.currentScene;
        final historyAfterRemote = h.controller.historyManager.undoCount;
        await h.vm.applySelectedCandidate();
        state = h.container.read(smartLayoutSessionViewModelProvider);
        final after = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
        );
        final checks = <String>[
          'phase failed=${state.phase == SmartLayoutSessionPhase.failed}',
          'stage apply=${state.failure?.stage == 'apply'}',
          'scene untouched=${identical(h.controller.currentScene, afterRemote)}',
          'history untouched=${after.undoCount == historyAfterRemote}',
          'failure recorded=${state.failure != null}',
        ];
        final ok =
            state.phase == SmartLayoutSessionPhase.failed &&
            state.failure?.stage == 'apply' &&
            identical(h.controller.currentScene, afterRemote) &&
            after.undoCount == historyAfterRemote;
        trace(ok ? 'S5a=true' : 'S5a=false :: ${checks.join(' | ')}');
        return TransactionMatrixCase(
          id: 'S5a-conflict-intersect',
          title: '写集相交：远端改写写集元素 → 拒绝且六态零副作用',
          passed: ok,
          checks: checks,
          before: before,
          after: after,
          failure: ok ? null : '相交冲突断言存在失败项',
        );
      } finally {
        await h.dispose();
      }
    });

    // ---- 不相交：远端新增无关元素 → 会话守卫 fail closed + 网关层
    // 重派一次成功（V3-502A CAS 语义：会话票据拒绝过时提交；网关在
    // 写集不相交时基于新 revision 重派恰好一次）。----
    final disjoint = await withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        var state = h.container.read(smartLayoutSessionViewModelProvider);
        if (state.validatedCards.isEmpty) {
          return TransactionMatrixCase(
            id: 'S5b-conflict-disjoint',
            title: '写集不相交：会话守卫拒绝过时票据 + 网关重派一次成功',
            passed: false,
            checks: const [],
            before: before,
            after: null,
            failure: '生成链未产出候选',
          );
        }
        final candidate = state.selectedValidatedCandidate!;
        // 远端新增无关元素（写集不相交；revision 前进）。
        h.controller.applyResult(AddElementResult(pageShape()));
        final historyAfterRemote = h.controller.historyManager.undoCount;

        // 会话路径：守卫四检拒绝过时票据（fail closed，零副作用）。
        await h.vm.applySelectedCandidate();
        state = h.container.read(smartLayoutSessionViewModelProvider);
        final guardRejected =
            state.phase == SmartLayoutSessionPhase.failed &&
            state.failure?.stage == 'apply' &&
            state.failure?.reason == 'revision-changed';
        final guardZeroSideEffect =
            h.controller.historyManager.undoCount == historyAfterRemote;

        // 网关路径：写集不相交 → 基于新 revision 重派恰好一次提交成功。
        final commitResult = h.scope.commitGateway.commit(candidate);
        final redispatched =
            commitResult is HistoryCommitted && commitResult.redispatched;
        final scene = h.controller.currentScene;
        final shapePresent = scene.elements.any(
          (e) => e.id.value == 'shape-1',
        );
        final textMoved =
            scene.elements.firstWhere((e) => e.id.value == 'text-1').version >
            1;
        final after = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
          ledgerOf: candidate,
        );
        final checks = <String>[
          'session guard rejected=$guardRejected(${state.failure?.reason})',
          'session zero side effect=$guardZeroSideEffect',
          'gateway redispatched=$redispatched',
          'remote shape present=$shapePresent',
          'text transformed=$textMoved',
          'undo+1=${after.undoCount == before.undoCount + 1}',
          'broadcast events=${h.broadcasts.length}',
        ];
        final ok =
            guardRejected &&
            guardZeroSideEffect &&
            redispatched &&
            shapePresent &&
            textMoved &&
            after.undoCount == before.undoCount + 1;
        trace(ok ? 'S5b=true' : 'S5b=false :: ${checks.join(' | ')}');
        return TransactionMatrixCase(
          id: 'S5b-conflict-disjoint',
          title: '写集不相交：会话守卫拒绝过时票据 + 网关重派一次成功',
          passed: ok,
          checks: checks,
          before: before,
          after: after,
          failure: ok ? null : '不相交重派断言存在失败项',
        );
      } finally {
        await h.dispose();
      }
    });
    return [intersect, disjoint];
  }

  // ==================== S6：纠错重跑 ====================

  static Future<TransactionMatrixCase> _correctionRerun(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    return withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        var state = h.container.read(smartLayoutSessionViewModelProvider);
        if (state.validatedCards.isEmpty) {
          return TransactionMatrixCase(
            id: 'S6-correction-rerun',
            title: '纠错重跑：旧候选全失效释放、新候选发布、Scene 零副作用',
            passed: false,
            checks: const [],
            before: before,
            after: null,
            failure: '生成链未产出候选',
          );
        }
        final oldCandidates = [
          for (final card in state.validatedCards) card.candidate,
        ];
        final oldImages = [
          for (final c in oldCandidates) c.snapshot.image,
        ];
        final historyBefore = h.controller.historyManager.undoCount;
        await h.vm.applyRegionCorrection(
          const RegionCorrectionIntent(
            kind: 'merge',
            subjectIds: ['text-1'],
          ),
        );
        state = h.container.read(smartLayoutSessionViewModelProvider);
        var oldDisposed = true;
        for (final image in oldImages) {
          if (!image.debugDisposed) oldDisposed = false;
        }
        final after = snapshotOf(
          h.controller,
          h.observer,
          broadcast: h.broadcasts,
        );
        final checks = <String>[
          'phase reviewing=${state.phase == SmartLayoutSessionPhase.reviewing}',
          'old candidates disposed=$oldDisposed',
          'new cards=${state.validatedCards.length}',
          'scene untouched=${after.sceneFingerprint == before.sceneFingerprint}',
          'history untouched=${after.undoCount == historyBefore}',
        ];
        final ok =
            state.phase == SmartLayoutSessionPhase.reviewing &&
            oldDisposed &&
            after.sceneFingerprint == before.sceneFingerprint &&
            after.undoCount == historyBefore;
        trace(ok ? 'S6=true' : 'S6=false :: ${checks.join(' | ')}');
        return TransactionMatrixCase(
          id: 'S6-correction-rerun',
          title: '纠错重跑：旧候选全失效释放、新候选发布、Scene 零副作用',
          passed: ok,
          checks: checks,
          before: before,
          after: after,
          failure: ok ? null : '纠错重跑断言存在失败项',
        );
      } finally {
        await h.dispose();
      }
    });
  }

  // ==================== S7：渲染/排名证据 ====================

  static Future<TransactionMatrixCase> _renderRankingEvidence(
    Future<(int, String)> Function(io.HttpRequest request) handler,
    void Function(String) trace,
  ) async {
    return withLoopback(handler, (serverUri, _) async {
      final h = harness(serverUri);
      try {
        final before = snapshotOf(h.controller, h.observer);
        await h.vm.startAnalysis();
        final state = h.container.read(smartLayoutSessionViewModelProvider);
        if (state.validatedCards.isEmpty) {
          return TransactionMatrixCase(
            id: 'S7-render-ranking',
            title: '渲染/排名证据：真实缩略图、Top3 分序+多样性、评分可还原',
            passed: false,
            checks: const [],
            before: before,
            after: null,
            failure: '生成链未产出候选',
          );
        }
        final checks = <String>[];
        var ok = true;
        // 渲染：每张卡有真实 renderer 缩略图（非零尺寸）。
        for (final card in state.validatedCards) {
          final image = card.thumbnail;
          final w = image.width;
          final hh = image.height;
          ok &= !image.debugDisposed && w > 0 && hh > 0;
          checks.add('thumbnail ${card.candidateId}=${w}x$hh');
        }
        // 排名：分数非升序排列（第 1 名 ≥ 后续）。
        final scores = [
          for (final card in state.validatedCards) card.score,
        ];
        for (var i = 1; i < scores.length; i++) {
          ok &= scores[i - 1] >= scores[i];
        }
        checks.add('rank scores desc=$scores');
        // 多样性：Top3 diversityKey 互异（不足 3 不补）。
        final keys = {
          for (final card in state.validatedCards) card.candidate.diversityKey,
        };
        ok &= keys.length == state.validatedCards.length;
        checks.add('diversity keys=$keys');
        // 评分可还原：Σ contribution == score（容差 1e-9）。
        for (final card in state.validatedCards) {
          final sum = card.scoreEntries
              .map((e) => e.contribution)
              .fold(0.0, (a, b) => a + b);
          final close = (sum - card.score).abs() < 1e-9;
          ok &= close;
          checks.add(
            'score restore ${card.candidateId}=$close'
            '(Σ$sum vs ${card.score})',
          );
        }
        trace(ok ? 'S7=true' : 'S7=false :: ${checks.join(' | ')}');
        return TransactionMatrixCase(
          id: 'S7-render-ranking',
          title: '渲染/排名证据：真实缩略图、Top3 分序+多样性、评分可还原',
          passed: ok,
          checks: checks,
          before: before,
          after: snapshotOf(
            h.controller,
            h.observer,
            broadcast: h.broadcasts,
          ),
          failure: ok ? null : '渲染/排名断言存在失败项',
        );
      } finally {
        await h.dispose();
      }
    });
  }
  /// 负载深度等价（preview=commit 口径）：元素 id 集一致；逐元素
  /// 排除 versionNonce/updated 后字段等价；version 数字一致。
  static bool _payloadEquivalent(Scene preview, Scene committed) {
    final previewIds = [
      for (final e in preview.orderedElements) e.id.value,
    ]..sort();
    final committedIds = [
      for (final e in committed.orderedElements) e.id.value,
    ]..sort();
    if (previewIds.length != committedIds.length) return false;
    for (var i = 0; i < previewIds.length; i++) {
      if (previewIds[i] != committedIds[i]) return false;
    }
    final committedById = {
      for (final e in committed.orderedElements) e.id.value: e,
    };
    for (final p in preview.orderedElements) {
      final c = committedById[p.id.value]!;
      if (p.version != c.version) return false;
      if (p is TextElement && c is TextElement) {
        if (p.text != c.text ||
            p.x != c.x ||
            p.y != c.y ||
            p.width != c.width ||
            p.height != c.height ||
            p.fontSize != c.fontSize ||
            p.fontFamily != c.fontFamily) {
          return false;
        }
      } else if (p is RectangleElement && c is RectangleElement) {
        if (p.x != c.x ||
            p.y != c.y ||
            p.width != c.width ||
            p.height != c.height ||
            p.angle != c.angle) {
          return false;
        }
      }
    }
    return true;
  }
}

/// 单场景夹具：controller + scope + 独立 revision 观察器 + VM 容器。
final class MatrixHarness {
  MatrixHarness({
    required this.controller,
    required this.scope,
    required this.observer,
    required this.container,
    required this.vm,
    required this.broadcasts,
  });

  final MarkdrawController controller;
  final SmartLayoutRealSessionScope scope;
  final SceneRevisionTracker observer;
  final ProviderContainer container;
  final SmartLayoutSessionViewModel vm;
  final List<String> broadcasts;

  Future<void> dispose() async {
    container.dispose();
    observer.dispose();
    scope.dispose();
    controller.dispose();
  }
}
