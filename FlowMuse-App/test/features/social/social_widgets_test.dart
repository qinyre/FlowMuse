import 'dart:ui' as ui;

import 'package:flow_muse/app/social_overlay.dart';
import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/view_models/conversation_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flow_muse/features/social/widgets/conversation_panel.dart';
import 'package:flow_muse/features/social/widgets/add_friend_dialog.dart';
import 'package:flow_muse/features/social/widgets/invitation_actions.dart';
import 'package:flow_muse/features/social/views/social_page.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class TestInbox extends SocialViewModel {
  TestInbox(this.initial);
  final SocialState initial;
  @override
  SocialState build() => initial;
  void update(SocialState value) => state = value;
  @override
  Future<void> refresh() async {}
}

class TestChat extends ConversationViewModel {
  TestChat(super.id);
  final sent = <String>[];
  final reads = <BigInt>[];
  void fail() => state = state.copyWith(error: '网络恢复中');
  void coverWithPending() => state = state.copyWith(
    pending: [
      PendingSocialMessage(
        'local',
        List.filled(100, '待发送的内容').join('\n'),
        failed: true,
      ),
    ],
  );
  @override
  ConversationState build() => ConversationState(
    loading: false,
    messages: [
      SocialMessage(
        id: 'one',
        conversationId: conversationId,
        seq: BigInt.one,
        senderId: 'B',
        clientMessageId: 'remote',
        text: '<b>纯文本消息</b>',
        createdAt: DateTime(2026, 9, 23, 13, 10),
      ),
    ],
  );
  @override
  Future<void> send(String text, {String? clientId}) async {
    sent.add(text);
  }

  @override
  Future<void> markVisibleRead(BigInt seq) async {
    reads.add(seq);
  }

  @override
  Future<void> refresh({bool older = false}) async {}
}

class TestLookup extends TestInbox {
  TestLookup() : super(const SocialState(status: SocialStatus.ready));
  final codes = <String>[];
  @override
  Future<SocialLookup?> lookup(String code) async {
    codes.add(code);
    return SocialLookup(testPerson, BigInt.zero, null);
  }
}

const testPerson = SocialPerson(
  id: 'B',
  name: '小林',
  friendCode: 'ABCD2345EFGH',
);

void main() {
  testWidgets('当前聊天对象在好友和消息列表中保持唯一选中背景，切换对象同步更新', (tester) async {
    tester.view.physicalSize = const Size(1200, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const peers = [
      testPerson,
      SocialPerson(id: 'C', name: '小周', friendCode: 'JKLM2345NPQR'),
    ];
    final state = SocialState(
      status: SocialStatus.ready,
      me: const SocialMe(
        person: SocialPerson(id: 'A', name: '我'),
        unreadCount: 0,
        pendingRequestCount: 0,
        textMessages: true,
      ),
      friends: [
        for (final p in peers)
          SocialRelationship(
            id: 'friend-${p.id}',
            person: p,
            requesterId: 'A',
            clientRequestId: p.id,
            status: 'accepted',
            version: BigInt.one,
            conversationId: 'chat-${p.id}',
          ),
      ],
      conversations: [
        for (final p in peers)
          SocialConversation(
            id: 'chat-${p.id}',
            person: p,
            canSend: true,
            lastSeq: BigInt.zero,
            readSeq: BigInt.zero,
            unreadCount: 0,
            updatedAt: 0,
          ),
      ],
    );
    Finder row(String name) =>
        find.widgetWithText(ListTile, name).hitTestable();
    final surfaceKey = GlobalKey();
    Future<void> expectPaintedSelection(String name, Color expected) async {
      final boundary =
          surfaceKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final rect = tester.getRect(row(name));
      final point =
          Offset(rect.left + 8, rect.center.dy) -
          tester.getTopLeft(find.byKey(surfaceKey));
      final pixel = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final rgba = data!.buffer.asUint8List(data.offsetInBytes);
        final color = Color.fromARGB(
          rgba[offset + 3],
          rgba[offset],
          rgba[offset + 1],
          rgba[offset + 2],
        );
        image.dispose();
        return color;
      });
      expect(pixel, expected, reason: '当前会话背景必须实际绘制出来，不能被父级背景盖住');
    }

    void expectSelection(String selected, String other) {
      final tile = tester.widget<ListTile>(row(selected));
      expect(tile.selected, isTrue);
      expect(
        tile.selectedTileColor?.a,
        greaterThan(0),
        reason: '选中行需有可见背景，不能仅改文字颜色',
      );
      expect(tester.widget<ListTile>(row(other)).selected, isFalse);
      expect(
        tester
            .widget<ConversationPanel>(find.byType(ConversationPanel))
            .person
            .name,
        selected,
      );
    }

    for (final config in [
      for (final preset in appThemePresets.where(
        (p) => p.id == AppThemeId.day || p.id == AppThemeId.night,
      ))
        for (final dialog in [false, true]) (preset: preset, dialog: dialog),
    ]) {
      final preset = config.preset;
      final theme = AppTheme.fromPreset(preset);
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey((preset.id, config.dialog)),
          overrides: [
            socialSessionProvider.overrideWithValue((
              userId: 'A',
              token: 'test',
            )),
            socialViewModelProvider.overrideWith(() => TestInbox(state)),
            for (final p in peers)
              conversationViewModelProvider(
                'chat-${p.id}',
              ).overrideWith(() => TestChat('chat-${p.id}')),
          ],
          child: RepaintBoundary(
            key: surfaceKey,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: config.dialog
                    ? Builder(
                        builder: (context) => TextButton(
                          onPressed: () => showSocialOverlay(context),
                          child: const Text('打开实际消息弹窗'),
                        ),
                      )
                    : ColoredBox(
                        color: theme.colorScheme.surface,
                        child: const SocialPage(),
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (config.dialog) {
        await tester.tap(find.text('打开实际消息弹窗'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('好友 · 2'));
      await tester.pumpAndSettle();
      await tester.tap(row('小林'));
      await tester.pumpAndSettle();
      expectSelection('小林', '小周');
      await expectPaintedSelection(
        '小林',
        theme.colorScheme.surfaceContainerHigh,
      );
      await tester.tap(row('小周'));
      await tester.pumpAndSettle();
      expectSelection('小周', '小林');
      await tester.tap(find.widgetWithText(Tab, '消息'));
      await tester.pumpAndSettle();
      expectSelection('小周', '小林');
      await expectPaintedSelection(
        '小周',
        theme.colorScheme.surfaceContainerHigh,
      );
      await tester.tap(row('小林'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('好友 · 2'));
      await tester.pumpAndSettle();
      expectSelection('小林', '小周');
      await expectPaintedSelection(
        '小林',
        theme.colorScheme.surfaceContainerHigh,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('邀请好友在 $width 宽度直接选人，不需要打开聊天', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inbox = TestInbox(
        SocialState(
          status: SocialStatus.ready,
          me: const SocialMe(
            person: testPerson,
            unreadCount: 0,
            pendingRequestCount: 0,
            textMessages: true,
            invitations: true,
          ),
          friends: [
            SocialRelationship(
              id: 'friend',
              person: testPerson,
              requesterId: 'A',
              clientRequestId: 'request',
              status: 'accepted',
              version: BigInt.one,
              conversationId: '',
            ),
          ],
        ),
      );
      final invited = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [socialViewModelProvider.overrideWith(() => inbox)],
          child: MaterialApp(
            home: Scaffold(
              body: InvitationActions(
                open: (_) async => fail('选人邀请不应打开收到的邀请'),
                send: (peer, supplement) async {
                  invited.add(peer.id);
                  expect(supplement, isNull);
                },
                child: const SocialPage(inviteFriends: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('小林'));
      await tester.pumpAndSettle();
      expect(invited, ['B']);
      expect(find.byType(ConversationPanel), findsNothing);
      expect(find.textContaining('安全'), findsNothing);
      inbox.update(const SocialState(status: SocialStatus.ready));
      await tester.pumpAndSettle();
      expect(find.text('好友邀请暂不可用，请复制房间码邀请协作者。'), findsOneWidget);
      expect(find.text('小林'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('好友页在 $width 宽度打开聊天，服务关闭即清空内容', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inbox = TestInbox(
        SocialState(
          status: SocialStatus.ready,
          me: const SocialMe(
            person: SocialPerson(
              id: 'A',
              name: '我',
              friendCode: 'FGHI2345ABCD',
            ),
            unreadCount: 1,
            pendingRequestCount: 0,
            textMessages: true,
          ),
          friends: [
            SocialRelationship(
              id: 'r',
              person: testPerson,
              requesterId: 'A',
              clientRequestId: 'c',
              status: 'accepted',
              version: BigInt.two,
              conversationId: 'chat',
            ),
          ],
          conversations: [
            SocialConversation(
              id: 'chat',
              person: testPerson,
              canSend: true,
              lastSeq: BigInt.one,
              readSeq: BigInt.zero,
              unreadCount: 1,
              updatedAt: 1,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialSessionProvider.overrideWithValue((
              userId: 'A',
              token: 'test',
            )),
            socialViewModelProvider.overrideWith(() => inbox),
            conversationViewModelProvider(
              'chat',
            ).overrideWith(() => TestChat('chat')),
          ],
          child: const MaterialApp(home: Scaffold(body: SocialPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的好友码'), findsOneWidget);
      await tester.tap(find.text('小林'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('<b>纯文本消息</b>')).dy -
            tester.getBottomLeft(find.text('私聊记录在云端保存')).dy,
        lessThan(120),
        reason: '少量消息应从标题下方排列，不能被推到聊天区底部',
      );
      expect(
        find.byTooltip('返回列表'),
        width < 820 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      inbox.update(const SocialState(status: SocialStatus.disabled));
      await tester.pumpAndSettle();
      expect(find.text('好友服务暂未开放，请稍后刷新。'), findsOneWidget);
      expect(find.text('小林'), findsNothing);
    });
  }
  testWidgets('好友查找只提交完整好友码并先展示公开资料', (tester) async {
    final inbox = TestLookup();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialSessionProvider.overrideWithValue((userId: 'A', token: 'test')),
          socialViewModelProvider.overrideWith(() => inbox),
        ],
        child: const MaterialApp(home: Scaffold(body: AddFriendDialog())),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.tap(find.text('查找'));
    await tester.pump();
    expect(inbox.codes, isEmpty);
    expect(find.text('请输入完整的 12 位好友码'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'abcd-2345-efgh');
    await tester.tap(find.text('查找'));
    await tester.pumpAndSettle();
    expect(inbox.codes, ['ABCD2345EFGH']);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('发送申请'), findsOneWidget);
  });
  testWidgets('窄屏大字体聊天显示纯文本，键盘发送；遮挡时不标已读', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chat = TestChat('chat');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialSessionProvider.overrideWithValue((userId: 'A', token: 'test')),
          socialViewModelProvider.overrideWith(
            () => TestInbox(const SocialState(status: SocialStatus.ready)),
          ),
          conversationViewModelProvider('chat').overrideWith(() => chat),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: ConversationPanel(
              id: 'chat',
              person: testPerson,
              canSend: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('<b>纯文本消息</b>'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const ValueKey('message-input')), '你好');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(chat.sent, ['你好']);
    final context = tester.element(find.byType(ConversationPanel));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('覆盖聊天')),
    );
    await tester.pumpAndSettle();
    final reads = chat.reads.length;
    chat.fail();
    await tester.pump();
    expect(chat.reads.length, reads);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    chat.reads.clear();
    chat.coverWithPending();
    await tester.pumpAndSettle();
    expect(chat.reads, isEmpty, reason: '最后一条入站消息在可视区域以外，不得已读');
    await tester.pumpWidget(const SizedBox());
  });
}
