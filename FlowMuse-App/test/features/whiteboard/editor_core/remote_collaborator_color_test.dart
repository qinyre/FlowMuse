import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/interactive/interactive_canvas_painter.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('成员顺序变化不改变既有协作者光标的实际颜色', () async {
    const first = RemoteCollaboratorOverlay(
      socketId: 'first',
      username: 'A',
      pointer: Point(50, 50),
      selectedElementIds: {},
    );
    const other = RemoteCollaboratorOverlay(
      socketId: 'other',
      username: 'B',
      pointer: Point(180, 180),
      selectedElementIds: {},
    );
    Future<List<int>> pixel(
      List<RemoteCollaboratorOverlay> collaborators,
    ) async {
      final recorder = ui.PictureRecorder();
      InteractiveCanvasPainter(
        viewport: const ViewportState(),
        remoteCollaborators: collaborators,
      ).paint(ui.Canvas(recorder), const ui.Size(256, 256));
      final picture = recorder.endRecording();
      final image = await picture.toImage(256, 256);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (53 * 256 + 53) * 4;
      final result = data.buffer.asUint8List(offset, 4).toList();
      image.dispose();
      picture.dispose();
      return result;
    }

    final before = await pixel([first]);
    expect(before.last, greaterThan(0));
    expect(await pixel([other, first]), before);
    expect(await pixel([first, other]), before);
  });
}
