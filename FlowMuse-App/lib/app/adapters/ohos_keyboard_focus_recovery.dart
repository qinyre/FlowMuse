import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import '../../shared/widgets/keyboard_focus_recovery.dart';

Widget wrapOhosKeyboardFocusRecovery(BuildContext context, Widget? child) {
  final content = child ?? const SizedBox.shrink();
  return defaultTargetPlatform == TargetPlatform.ohos
      ? KeyboardFocusRecovery(child: content)
      : content;
}
