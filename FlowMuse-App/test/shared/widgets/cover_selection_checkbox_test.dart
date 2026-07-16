import 'package:flow_muse/shared/widgets/cover_selection_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('封面多选控件为圆形并响应点击', (tester) async {
    var changed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverSelectionCheckbox(
            selected: false,
            onChanged: () => changed = true,
          ),
        ),
      ),
    );

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.shape, isA<CircleBorder>());
    expect(
      find.descendant(
        of: find.byType(CoverSelectionCheckbox),
        matching: find.byType(Material),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(Checkbox));
    expect(changed, isTrue);
  });
}
