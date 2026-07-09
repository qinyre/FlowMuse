import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses HarmonyOS platform channel renderer on OHOS', () {
    expect(
      createDefaultPdfPageRenderer(platform: TargetPlatform.ohos),
      isA<PlatformPdfPageRenderer>(),
    );
  });

  test('uses pdfx renderer on non-OHOS platforms', () {
    expect(
      createDefaultPdfPageRenderer(platform: TargetPlatform.android),
      isA<PdfxPdfPageRenderer>(),
    );
  });

  test('uses unsupported renderer on platforms without a PDF renderer', () {
    expect(
      createDefaultPdfPageRenderer(platform: TargetPlatform.linux),
      isA<UnsupportedPdfPageRenderer>(),
    );
  });
}
