import 'package:flutter/foundation.dart';

import '../editor/property_panel_state.dart';
import '../editor/tools/freedraw_tool.dart';

@immutable
class LocalWetInkFrame {
  const LocalWetInkFrame({
    required this.strokeEpoch,
    required this.view,
    required this.style,
    this.maxInputSeq,
  });

  final int strokeEpoch;
  final ActiveFreedrawView view;
  final ElementStyle style;
  final int? maxInputSeq;
}

class LocalWetInkState extends ChangeNotifier {
  LocalWetInkFrame? _frame;
  int _revision = 0;

  LocalWetInkFrame? get frame => _frame;
  int get revision => _revision;

  void publish(LocalWetInkFrame frame) {
    _frame = frame;
    _revision++;
    notifyListeners();
  }

  void clear({bool notify = true}) {
    if (_frame == null) return;
    _frame = null;
    _revision++;
    if (notify) notifyListeners();
  }
}
