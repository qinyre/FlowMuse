import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/view_models/conversation_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flow_muse/features/social/widgets/conversation_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class TestInbox extends SocialViewModel {
  TestInbox(this.initial);
  final SocialState initial;
  @override
  SocialState build() => initial;
  @override
  Future<void> refresh() async {}
}

class TestChat extends ConversationViewModel {
  TestChat(super.id);
  final sent = <String>[];
  final reads = <BigInt>[];
  void fail() => state = state.copyWith(error: '网络恢复中');
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

const testPerson = SocialPerson(
  id: 'B',
  name: '小林',
  friendCode: 'ABCD2345EFGH',
);

void main() {
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
    await tester.pumpWidget(const SizedBox());
  });
}
