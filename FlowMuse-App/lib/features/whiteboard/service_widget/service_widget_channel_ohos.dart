import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'recent_whiteboard_snapshot.dart';

enum ServiceWidgetLaunchAction { resumeLastWhiteboard }

class ServiceWidgetChannelOhos {
  const ServiceWidgetChannelOhos();

  static const _channel = MethodChannel('flow_muse/service_widget');

  Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>(
          'updateLastWhiteboard', snapshot.toJson());
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<ServiceWidgetLaunchAction?> takePendingLaunchAction() async {
    try {
      final action =
          await _channel.invokeMethod<String>('takePendingLaunchAction');
      return action == 'resumeLastWhiteboard'
          ? ServiceWidgetLaunchAction.resumeLastWhiteboard
          : null;
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
