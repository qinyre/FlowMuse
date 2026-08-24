import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_agent_models.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/models/ai_visual_attachment.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_agent_repository.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_prompt_store.dart';
import 'package:flow_muse/features/whiteboard/ai_assistant/views/ai_agent_dialog.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/models/speech_recognition_event.dart';
import 'package:flow_muse/features/whiteboard/speech_recognition/services/speech_recognition_service.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kTinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  AiVisualAttachment attachmentOf(
    String label, [
    AiVisualAttachmentKind kind = AiVisualAttachmentKind.selection,
  ]) => AiVisualAttachment(
    sourceLabel: label,
    mimeType: 'image/png',
    bytes: base64Decode(kTinyPng),
    kind: kind,
  );
  testWidgets('语音识别结果填入 AI 指令且不会重复追加', (tester) async {
    final speech = _FakeSpeechRecognitionService();
    addTearDown(speech.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAgentPanel(
            repository: _FakeAiAgentRepository(),
            noteTitle: '测试笔记',
            texts: const [],
            contextTruncated: false,
            contextLabel: '当前笔记',
            promptStore: AiPromptStore(_MemorySettings()),
            speechRecognitionService: speech,
            onApply: (_) async {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('语音输入'));
    speech.emit(const SpeechRecognitionResult('生成一份总结', isFinal: true));
    speech.emit(const SpeechRecognitionResult('重复结果', isFinal: true));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '生成一份总结',
    );
  });

  testWidgets('快捷指令可填充输入且只应用勾选动作', (tester) async {
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onApply: (response) async => applied = response,
    );

    await tester.tap(find.text('待办'));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '提取待办事项',
    );

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    final renameAction = find.widgetWithText(CheckboxListTile, '重命名笔记');
    await tester.ensureVisible(renameAction);
    await tester.tap(renameAction);
    await tester.pump();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(applied!.actions, hasLength(1));
    expect(applied!.actions.single.tool, AiAgentTool.insertText);
  });

  testWidgets('追问携带上一轮动作且编辑后的内容才会应用', (tester) async {
    final repository = _FakeAiAgentRepository();
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: repository,
      onApply: (response) async => applied = response,
    );

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '再精简一点');
    await tester.tap(find.text('追问修改'));
    await tester.pumpAndSettle();

    expect(repository.conversations.last, hasLength(1));
    expect(repository.conversations.last.single.response.actions, hasLength(2));
    await tester.enterText(find.byType(TextField).first, '改成三条待办');
    await tester.pump();
    await tester.tap(find.text('追问修改'));
    await tester.pumpAndSettle();
    expect(repository.conversations.last, hasLength(2));
    final insertField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == '精简后的总结',
    );
    await tester.enterText(insertField, '用户修改后的总结');
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(
      applied!.actions
          .singleWhere((action) => action.tool == AiAgentTool.insertText)
          .value,
      '用户修改后的总结',
    );
  });

  testWidgets('AI 回复渲染 Markdown 且应用后面板保持打开', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: const AiAgentResponse(
          message: '**重点**\n\n- 第一项',
          actions: [AiAgentAction(tool: AiAgentTool.insertText, value: '总结内容')],
        ),
      ),
      onApply: (_) async {},
    );

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(find.text('AI 笔记助手'), findsOneWidget);
    expect(find.text('追问修改'), findsOneWidget);
  });

  testWidgets('清除对话会清空当前回复和后续请求历史', (tester) async {
    final repository = _FakeAiAgentRepository();
    await _openDialog(tester, repository: repository, onApply: (_) async {});

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('清除对话'), findsOneWidget);

    await tester.tap(find.byTooltip('清除对话'));
    await tester.pump();
    expect(find.text('准备应用'), findsNothing);
    expect(find.byTooltip('清除对话'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '重新开始');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(repository.conversations.last, isEmpty);
  });

  testWidgets('取消生成会终止令牌并忽略迟到响应', (tester) async {
    final completer = Completer<AiAgentResponse>();
    final repository = _FakeAiAgentRepository(completer: completer);
    await _openDialog(tester, repository: repository, onApply: (_) async {});

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.tap(find.text('取消生成'));
    await tester.pump();

    expect(repository.cancelToken!.isCancelled, isTrue);
    expect(find.text('已取消生成'), findsOneWidget);
    completer.complete(_FakeAiAgentRepository.firstResponse);
    await tester.pump();
    expect(find.text('准备应用'), findsNothing);
  });

  testWidgets('空笔记可直接对话且不显示应用操作', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: const AiAgentResponse(message: '这是直接回答', actions: []),
      ),
      texts: const [],
      onApply: (_) async {},
    );

    await tester.enterText(find.byType(TextField).first, '帮我构思一个故事');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('这是直接回答'), findsOneWidget);
    expect(find.text('确认后将执行：'), findsNothing);
    expect(find.text('确认应用'), findsNothing);
    expect(find.text('追问修改'), findsOneWidget);
  });

  testWidgets('右侧面板不会用遮罩阻断画布操作', (tester) async {
    var canvasTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => canvasTaps++,
                  child: const Text('画布操作'),
                ),
              ),
              SizedBox(
                width: 400,
                child: AiAgentPanel(
                  repository: _FakeAiAgentRepository(),
                  noteTitle: '测试笔记',
                  texts: const [],
                  contextTruncated: false,
                  contextLabel: '当前笔记（暂无文字）',
                  promptStore: AiPromptStore(_MemorySettings()),
                  onApply: (_) async {},
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('画布操作'));
    expect(canvasTaps, 1);
  });

  testWidgets('面板打开后发送时读取最新文本框选区', (tester) async {
    var context = const (
      noteTitle: '测试笔记',
      texts: [AiNoteText(id: 'text-a', text: '旧选区')],
      truncated: false,
      label: '当前选区（1 个文本框）',
      hasSelection: false,
    );
    final repository = _FakeAiAgentRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAgentPanel(
            repository: repository,
            noteTitle: context.noteTitle,
            texts: context.texts,
            contextTruncated: context.truncated,
            contextLabel: context.label,
            contextProvider: () async => context,
            promptStore: AiPromptStore(_MemorySettings()),
            onApply: (_) async {},
            onClose: () {},
          ),
        ),
      ),
    );

    context = const (
      noteTitle: '测试笔记',
      texts: [AiNoteText(id: 'text-b', text: '新选区')],
      truncated: false,
      label: '当前选区（1 个文本框）',
      hasSelection: false,
    );
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(repository.receivedTexts.single.single.id, 'text-b');
    expect(repository.receivedTexts.single.single.text, '新选区');
  });

  testWidgets('思维导图动作展示结构并经确认应用', (tester) async {
    final action = AiAgentAction.fromJson({
      'tool': 'generate_mindmap',
      'arguments': {
        'root': {
          'text': '中心主题',
          'children': [
            {'text': '分支', 'children': <Object?>[]},
          ],
        },
      },
    });
    AiAgentResponse? applied;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: AiAgentResponse(message: '已生成', actions: [action]),
      ),
      onApply: (response) async => applied = response,
    );

    await tester.tap(find.text('思维导图'));
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('生成思维导图'), findsOneWidget);
    expect(find.textContaining('中心主题'), findsOneWidget);
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(applied!.actions.single.tool, AiAgentTool.generateMindmap);
  });

  testWidgets('应用思维导图失败时展示可理解的 StateError 消息', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(
        response: AiAgentResponse(
          message: '已生成',
          actions: [
            AiAgentAction.fromJson({
              'tool': 'generate_mindmap',
              'arguments': {
                'root': {'text': '超大主题', 'children': <Object?>[]},
              },
            }),
          ],
        ),
      ),
      onApply: (_) async {
        throw StateError('思维导图超出页面，请减少分支后重试');
      },
    );

    await tester.enterText(find.byType(TextField).first, '生成思维导图');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();

    expect(find.text('思维导图超出页面，请减少分支后重试'), findsOneWidget);
  });

  testWidgets('开面板自动捕获的附件显示缩略条、隐私文案并随请求发送', (tester) async {
    final repository = _FakeAiAgentRepository();
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () async => attachmentOf('当前选区'),
      onApply: (_) async {},
    );

    expect(find.text('当前选区'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 1 张图片'), findsOneWidget);
    expect(find.textContaining('会随打开面板或点击视觉指令自动加入或更新'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '解释这里');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(repository.receivedAttachments.last, hasLength(1));
  });

  testWidgets('选区存在时显示选区快捷指令并可填充', (tester) async {
    final repository = _FakeAiAgentRepository();
    await _openDialog(
      tester,
      repository: repository,
      hasSelection: true,
      onApply: (_) async {},
    );

    expect(find.text('解释这里'), findsOneWidget);
    expect(find.text('检查公式'), findsOneWidget);
    expect(find.text('整理文字'), findsOneWidget);
    expect(find.text('整理成导图'), findsOneWidget);
    expect(find.text('总结'), findsNothing);

    await tester.tap(find.text('解释这里'));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '解释这里的内容',
    );
  });

  testWidgets('附件生成中显示视觉阶段状态并在完成后渲染回复', (tester) async {
    final completer = Completer<AiAgentResponse>();
    final repository = _FakeAiAgentRepository(completer: completer);
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () async => attachmentOf('当前选区'),
      onApply: (_) async {},
    );

    await tester.enterText(find.byType(TextField).first, '解释这里');
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(find.text('正在结合选区图像与笔记内容生成…'), findsOneWidget);

    completer.complete(const AiAgentResponse(message: '看懂了', actions: []));
    await tester.pumpAndSettle();
    expect(find.text('看懂了'), findsOneWidget);
  });

  testWidgets('快捷指令捕获在途时点发送，请求等待捕获完成后携带附件', (tester) async {
    final repository = _FakeAiAgentRepository();
    var selectionCalls = 0;
    final refreshCapture = Completer<AiVisualAttachment?>();
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future.value(attachmentOf('开面板截图'));
        }
        return refreshCapture.future;
      },
      hasSelection: true,
      onApply: (_) async {},
    );
    // 开面板被动捕获（第 1 次）完成。
    await tester.pumpAndSettle();

    // 点击快捷指令触发刷新捕获（第 2 次，挂起），随后立即发送。
    await tester.tap(find.text('解释这里'));
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();

    refreshCapture.complete(attachmentOf('刷新后截图'));
    await tester.pumpAndSettle();

    expect(repository.receivedAttachments.last, hasLength(1));
    expect(repository.receivedAttachments.last.single.sourceLabel, '刷新后截图');
  });

  testWidgets('在途捕获失败时移除过期槽并以文字上下文完成发送', (tester) async {
    final repository = _FakeAiAgentRepository();
    var selectionCalls = 0;
    final refreshCapture = Completer<AiVisualAttachment?>();
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future.value(attachmentOf('开面板截图'));
        }
        return refreshCapture.future;
      },
      hasSelection: true,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('开面板截图'), findsOneWidget);

    // 点击快捷指令触发刷新捕获（指令由 chip 填入），随后立即发送。
    await tester.tap(find.text('解释这里'));
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();

    refreshCapture.completeError(StateError('图片解码失败，请重新打开笔记后重试'));
    await tester.pumpAndSettle();

    expect(find.textContaining('本次发送将以文字上下文为主'), findsOneWidget);
    expect(find.text('开面板截图'), findsNothing);
    expect(repository.receivedAttachments.last, isEmpty);
  });

  testWidgets('快捷指令遇纯文本选区时移除活动槽且手动附件保留', (tester) async {
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future.value(attachmentOf('开面板截图'));
        }
        return Future<AiVisualAttachment?>.value(null); // 用户改选纯文本
      },
      onCaptureCurrentPdfPage: () async =>
          attachmentOf('PDF 第 9 页', AiVisualAttachmentKind.pdfPage),
      hasSelection: true,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    // 手动添加 PDF 页（追加式，不登记活动槽）。
    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    expect(find.text('PDF 第 9 页'), findsOneWidget);

    // 改选纯文本后点视觉快捷指令：null → 活动槽移除，手动附件不动。
    await tester.tap(find.text('解释这里'));
    await tester.pumpAndSettle();

    expect(find.text('开面板截图'), findsNothing);
    expect(find.text('PDF 第 9 页'), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 1 张图片'), findsOneWidget);
  });

  testWidgets('满额且槽空时快捷指令仅提示不驱逐手动附件', (tester) async {
    var pdfCalls = 0;
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future<AiVisualAttachment?>.value(null); // 开面板无视觉选区
        }
        return Future.value(attachmentOf('新选区')); // 快捷指令捕获返回真实图
      },
      onCaptureCurrentPdfPage: () {
        pdfCalls++;
        return Future.value(
          attachmentOf('PDF 第 $pdfCalls 页', AiVisualAttachmentKind.pdfPage),
        );
      },
      hasSelection: true,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('PDF 页'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('仅发送附件条中显示的 3 张图片'), findsOneWidget);

    await tester.tap(find.text('解释这里'));
    await tester.pumpAndSettle();

    expect(find.text('附件已满，移除一张以附带当前选区'), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 3 张图片'), findsOneWidget);
    expect(find.text('PDF 第 1 页'), findsOneWidget);
    expect(find.text('PDF 第 3 页'), findsOneWidget);
  });

  testWidgets('槽占用时快捷指令替换为计数中性操作不受满额限制', (tester) async {
    var selectionCalls = 0;
    var pdfCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        return Future.value(attachmentOf(selectionCalls == 1 ? '旧选区' : '新选区'));
      },
      onCaptureCurrentPdfPage: () {
        pdfCalls++;
        return Future.value(
          attachmentOf('PDF 第 $pdfCalls 页', AiVisualAttachmentKind.pdfPage),
        );
      },
      hasSelection: true,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('旧选区'), findsOneWidget);

    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF 页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('仅发送附件条中显示的 3 张图片'), findsOneWidget);

    // 条已满额但槽占用：替换（移除旧槽+加入新槽）计数中性，不受限。
    await tester.tap(find.text('解释这里'));
    await tester.pumpAndSettle();

    expect(find.text('旧选区'), findsNothing);
    expect(find.text('新选区'), findsOneWidget);
    expect(find.text('PDF 第 1 页'), findsOneWidget);
    expect(find.text('PDF 第 2 页'), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 3 张图片'), findsOneWidget);
  });

  testWidgets('不传捕获回调时附件区整体不渲染（旧调用方零回归）', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onApply: (_) async {},
    );

    expect(find.text('选区截图'), findsNothing);
    expect(find.text('PDF 页'), findsNothing);
    expect(find.textContaining('本次提问仅发送文字上下文'), findsNothing);
    expect(find.textContaining('仅发送附件条中显示'), findsNothing);
  });

  testWidgets('手动点击选区截图 chip 追加附件并显示 KiB 大小', (tester) async {
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        return Future.value(
          attachmentOf(selectionCalls == 1 ? '开面板截图' : '手动选区'),
        );
      },
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    expect(find.text('手动选区'), findsOneWidget);
    // 两张 70B 基准 PNG 的 KiB 取整均为 0。
    expect(find.text('0 KiB'), findsNWidgets(2));
    expect(find.textContaining('仅发送附件条中显示的 2 张图片'), findsOneWidget);
  });

  testWidgets('达上限后添加 chips 禁用', (tester) async {
    var pdfCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () async => null,
      onCaptureCurrentPdfPage: () {
        pdfCalls++;
        return Future.value(
          attachmentOf('PDF 第 $pdfCalls 页', AiVisualAttachmentKind.pdfPage),
        );
      },
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('PDF 页'));
      await tester.pumpAndSettle();
    }

    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, '选区截图'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, 'PDF 页'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('开面板被动捕获失败走内联提示而非全局错误', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () async => throw StateError('图片解码失败，请重新打开笔记后重试'),
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('图片解码失败'), findsOneWidget);
    expect(find.textContaining('本次发送将以文字上下文为主'), findsNothing);
  });

  testWidgets('手动 chip 遇无可捕获视觉内容时展示引导提示', (tester) async {
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () async => null,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    expect(find.text('当前选区没有可截图的视觉内容'), findsOneWidget);
  });

  testWidgets('手动 chip 捕获失败在错误容器展示消息', (tester) async {
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future<AiVisualAttachment?>.value(null); // 被动捕获静默
        }
        return Future<AiVisualAttachment?>.error(StateError('选区渲染失败'));
      },
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    expect(find.text('选区渲染失败'), findsOneWidget);
  });

  testWidgets('移除附件后缩略条消失且可经快捷指令重建活动槽', (tester) async {
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        if (selectionCalls == 1) {
          return Future.value(attachmentOf('开面板截图'));
        }
        return Future.value(attachmentOf('刷新后截图'));
      },
      hasSelection: true,
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('开面板截图'), findsOneWidget);

    await tester.tap(find.byTooltip('移除图片'));
    await tester.pumpAndSettle();
    expect(find.text('开面板截图'), findsNothing);

    // 移除后槽引用已清空：快捷指令按"槽空加入"路径重建。
    await tester.tap(find.text('解释这里'));
    await tester.pumpAndSettle();
    expect(find.text('刷新后截图'), findsOneWidget);
  });

  testWidgets('loading 期间添加与移除均禁用', (tester) async {
    final completer = Completer<AiAgentResponse>();
    final repository = _FakeAiAgentRepository(completer: completer);
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () async => attachmentOf('开面板截图'),
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pump();

    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, '选区截图'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('ai-attachment-remove')),
          )
          .onPressed,
      isNull,
    );

    completer.complete(_FakeAiAgentRepository.firstResponse);
    await tester.pumpAndSettle();
  });

  testWidgets('追问时附件随每次请求重发', (tester) async {
    final repository = _FakeAiAgentRepository();
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () async => attachmentOf('开面板截图'),
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '再精简一点');
    await tester.tap(find.text('追问修改'));
    await tester.pumpAndSettle();

    expect(repository.receivedAttachments, hasLength(2));
    expect(repository.receivedAttachments.last, hasLength(1));
  });

  testWidgets('清除对话同时清空附件', (tester) async {
    final repository = _FakeAiAgentRepository();
    await _openDialog(
      tester,
      repository: repository,
      onCaptureSelection: () async => attachmentOf('开面板截图'),
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清除对话'));
    await tester.pumpAndSettle();

    expect(find.text('开面板截图'), findsNothing);
    expect(find.text('本次提问仅发送文字上下文'), findsOneWidget);
  });

  testWidgets('未传框选截图回调时选区截图芯片仍走元素捕获路径（零回归锚点）',
      (tester) async {
    // Given: 仅传 onCaptureSelection 的既有调用方，未传 onRegionCapture。
    var selectionCalls = 0;
    await _openDialog(
      tester,
      repository: _FakeAiAgentRepository(),
      onCaptureSelection: () {
        selectionCalls++;
        return Future.value(
          attachmentOf(selectionCalls == 1 ? '开面板截图' : '手动选区'),
        );
      },
      onApply: (_) async {},
    );
    await tester.pumpAndSettle();

    // When: 点击「选区截图」芯片。
    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    // Then: 元素捕获结果加入附件条，行为与改造前一致。
    expect(find.text('手动选区'), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 2 张图片'), findsOneWidget);
  });

  testWidgets('框选截图完成加入附件并更新计数与隐私文案', (tester) async {
    // Given: 面板经 onRegionCapture 接入页面级框选流程。
    await _openPanel(
      tester,
      repository: _FakeAiAgentRepository(),
      onRegionCapture: () async => attachmentOf('框选截图'),
      onApply: (_) async {},
    );
    expect(find.textContaining('本次提问仅发送文字上下文'), findsOneWidget);

    // When: 点击「选区截图」芯片，页面框选流程提交一张截图。
    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    // Then: 缩略图与标签展示，计数与隐私文案随附件更新。
    expect(find.text('框选截图'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('仅发送附件条中显示的 1 张图片'), findsOneWidget);
    expect(find.textContaining('框选截图包含框内全部可见内容'), findsOneWidget);
  });

  testWidgets('框选取消返回 null 时静默无提示', (tester) async {
    // Given: 页面框选流程返回 null（用户取消）。
    await _openPanel(
      tester,
      repository: _FakeAiAgentRepository(),
      onRegionCapture: () async => null,
      onApply: (_) async {},
    );

    // When: 点击「选区截图」芯片。
    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    // Then: 无新附件、无引导提示、无错误容器。
    expect(find.textContaining('本次提问仅发送文字上下文'), findsOneWidget);
    expect(find.textContaining('当前选区没有可截图的视觉内容'), findsNothing);
    expect(find.textContaining('失败'), findsNothing);
  });

  testWidgets('框选流程抛错时错误容器展示消息', (tester) async {
    // Given: 页面框选流程抛出 StateError。
    await _openPanel(
      tester,
      repository: _FakeAiAgentRepository(),
      onRegionCapture: () async =>
          throw StateError('请先在画布选中要发送的内容'),
      onApply: (_) async {},
    );

    // When: 点击「选区截图」芯片。
    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    // Then: 错误消息出现在全局错误容器。
    expect(find.text('请先在画布选中要发送的内容'), findsOneWidget);
  });

  testWidgets('框选截图达满额后芯片禁用', (tester) async {
    // Given: 通过 onRegionCapture 连续添加至满额。
    await _openPanel(
      tester,
      repository: _FakeAiAgentRepository(),
      onRegionCapture: () async => attachmentOf('框选截图'),
      onApply: (_) async {},
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('选区截图'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('仅发送附件条中显示的 3 张图片'), findsOneWidget);

    // When: 已达满额。
    // Then: 「选区截图」芯片不可再点。
    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, '选区截图'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('框选截图附件随发送与追问重发', (tester) async {
    // Given: 面板接入 onRegionCapture 并已添加一张框图。
    final repository = _FakeAiAgentRepository();
    await _openPanel(
      tester,
      repository: repository,
      onRegionCapture: () async => attachmentOf('框选截图'),
      onApply: (_) async {},
    );
    await tester.tap(find.text('选区截图'));
    await tester.pumpAndSettle();

    // When: 发送一次，再追问一次。
    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '再精简一点');
    await tester.tap(find.text('追问修改'));
    await tester.pumpAndSettle();

    // Then: 每次请求都携带该框选截图附件。
    expect(repository.receivedAttachments, hasLength(2));
    expect(repository.receivedAttachments.last, hasLength(1));
    expect(
      repository.receivedAttachments.last.single.sourceLabel,
      '框选截图',
    );
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  required AiAgentRepository repository,
  required Future<void> Function(AiAgentResponse) onApply,
  List<AiNoteText> texts = const [AiNoteText(id: 'text-1', text: '测试内容')],
  Future<AiVisualAttachment?> Function()? onCaptureSelection,
  Future<AiVisualAttachment?> Function()? onCaptureCurrentPdfPage,
  bool hasSelection = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAiAgentDialog(
            context: context,
            repository: repository,
            promptStore: AiPromptStore(_MemorySettings()),
            noteTitle: '测试笔记',
            texts: texts,
            hasSelection: hasSelection,
            onCaptureSelection: onCaptureSelection,
            onCaptureCurrentPdfPage: onCaptureCurrentPdfPage,
            onApply: onApply,
          ),
          child: const Text('打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

/// 直构 AiAgentPanel 以传入 onRegionCapture（showAiAgentDialog 为
/// 零回归故意不传此参数，页面级调用方会在 T4 中自行构造面板）。
Future<void> _openPanel(
  WidgetTester tester, {
  required AiAgentRepository repository,
  required Future<void> Function(AiAgentResponse) onApply,
  Future<AiVisualAttachment?> Function()? onRegionCapture,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiAgentPanel(
          repository: repository,
          noteTitle: '测试笔记',
          texts: const [AiNoteText(id: 'text-1', text: '测试内容')],
          contextTruncated: false,
          contextLabel: '当前笔记',
          onRegionCapture: onRegionCapture,
          promptStore: AiPromptStore(_MemorySettings()),
          onApply: onApply,
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAiAgentRepository extends AiAgentRepository {
  _FakeAiAgentRepository({this.completer, this.response = firstResponse});

  static const firstResponse = AiAgentResponse(
    message: '准备应用',
    actions: [
      AiAgentAction(tool: AiAgentTool.renameNote, value: '新标题'),
      AiAgentAction(tool: AiAgentTool.insertText, value: '总结内容'),
    ],
  );
  final Completer<AiAgentResponse>? completer;
  final AiAgentResponse response;
  final conversations = <List<AiAgentConversationTurn>>[];
  final receivedTexts = <List<AiNoteText>>[];
  final receivedAttachments = <List<AiVisualAttachment>>[];
  NativeHttpCancelToken? cancelToken;

  @override
  Future<AiAgentResponse> run({
    required String instruction,
    required String noteTitle,
    required List<AiNoteText> texts,
    List<AiAgentConversationTurn> conversation = const [],
    List<AiVisualAttachment> attachments = const [],
    NativeHttpCancelToken? cancelToken,
  }) async {
    conversations.add(List.unmodifiable(conversation));
    receivedTexts.add(texts);
    receivedAttachments.add(attachments);
    this.cancelToken = cancelToken;
    if (completer != null) return completer!.future;
    if (conversation.isNotEmpty) {
      return const AiAgentResponse(
        message: '已按追问修改',
        actions: [
          AiAgentAction(tool: AiAgentTool.renameNote, value: '新标题'),
          AiAgentAction(tool: AiAgentTool.insertText, value: '精简后的总结'),
        ],
      );
    }
    return response;
  }
}

class _MemorySettings extends LocalSettingsRepository {
  _MemorySettings() : super(() async => throw UnsupportedError('unused'));

  final values = <String, String>{};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final _events = StreamController<SpeechRecognitionEvent>.broadcast();

  void emit(SpeechRecognitionEvent event) => _events.add(event);

  @override
  Stream<SpeechRecognitionEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start({String locale = 'zh-CN'}) async {
    emit(const SpeechRecognitionStateChanged(SpeechRecognitionState.listening));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _events.close();
}
