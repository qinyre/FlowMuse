import 'package:flow_muse/shared/utils/app_haptics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  for (final error in [
    PlatformException(code: 'unavailable'),
    MissingPluginException('unsupported'),
  ]) {
    test('触感不可用不影响面板操作：${error.runtimeType}', () async {
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => throw error,
      );
      await AppHaptics.panelOpen();
      await AppHaptics.selection();
    });
  }
}
