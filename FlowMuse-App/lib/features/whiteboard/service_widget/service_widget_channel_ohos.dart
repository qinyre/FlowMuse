import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'recent_whiteboard_snapshot.dart';

enum ServiceWidgetLaunchAction { resumeLastWhiteboard, createNote }

class ServiceWidgetChannelOhos {
  const ServiceWidgetChannelOhos();

  static const _channel = MethodChannel('flow_muse/service_widget');

  Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot) async {
    debugPrint('[ServiceWidget] channel.updateLastWhiteboard invoking: ${snapshot.toJson()}');
    try {
      final result = await _channel.invokeMethod<String>(
          'updateLastWhiteboard', snapshot.toJson());
      debugPrint('[ServiceWidget] channel.updateLastWhiteboard succeeded: $result');
    } on MissingPluginException catch (e) {
      debugPrint('[ServiceWidget] channel.updateLastWhiteboard MissingPluginException: $e');
      return;
    } on PlatformException catch (e) {
      debugPrint('[ServiceWidget] channel.updateLastWhiteboard PlatformException: $e');
      return;
    } catch (e) {
      debugPrint('[ServiceWidget] channel.updateLastWhiteboard error: $e');
      return;
    }
  }

  Future<ServiceWidgetLaunchAction?> takePendingLaunchAction() async {
    try {
      final action =
          await _channel.invokeMethod<String>('takePendingLaunchAction');
      return switch (action) {
        'resumeLastWhiteboard' => ServiceWidgetLaunchAction.resumeLastWhiteboard,
        'createNote' => ServiceWidgetLaunchAction.createNote,
        _ => null,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void setLaunchListener(VoidCallback onRequested) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchActionEnqueued') {
        onRequested();
      }
      return null;
    });
  }
}
