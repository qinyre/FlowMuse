import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/view_models/whiteboard_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp() {
  final hub = MemoryRealtimeRoomHub();
  return ProviderScope(
    overrides: [
      collaborationRepositoryProvider.overrideWith(
        (ref) => CollaborationRepository(
          transport: MemoryRealtimeTransport(hub: hub, socketId: 'test-client'),
        ),
      ),
    ],
    child: FlowMuseApp(),
  );
}

void main() {
  testWidgets(
    'creates an Excalidraw-style collaboration room from whiteboard',
    (WidgetTester tester) async {
      await tester.pumpWidget(_testApp());

      await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建房间'));
      await tester.pumpAndSettle();

      expect(find.text('协作中'), findsOneWidget);
      expect(find.textContaining('#room='), findsOneWidget);
    },
  );
}
