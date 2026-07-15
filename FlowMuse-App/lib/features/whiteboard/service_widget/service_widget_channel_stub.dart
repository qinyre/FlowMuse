import 'package:flutter/widgets.dart';
import 'recent_whiteboard_snapshot.dart';

enum ServiceWidgetLaunchAction { resumeLastWhiteboard }

class ServiceWidgetChannelOhos {
  const ServiceWidgetChannelOhos();

  Future<void> updateLastWhiteboard(RecentWhiteboardSnapshot snapshot) async {}

  Future<ServiceWidgetLaunchAction?> takePendingLaunchAction() async => null;

  void setLaunchListener(VoidCallback onRequested) {}
}
