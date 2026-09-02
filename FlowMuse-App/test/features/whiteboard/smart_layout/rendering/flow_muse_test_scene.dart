import 'dart:convert';
import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';

/// 1×1 红色 PNG（真实可解码字节，非伪造）。
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
  'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 渲染测试场景：形状 + 文本 + 图片（默认携带真实文件字节）。
Scene buildTestScene({bool withImageFile = true}) {
  var scene = Scene()
      .addElement(
        RectangleElement(
          id: ElementId('shape-1'),
          x: 10,
          y: 10,
          width: 40,
          height: 30,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      )
      .addElement(
        TextElement(
          id: ElementId('text-1'),
          x: 100,
          y: 40,
          width: 200,
          height: 28,
          text: '真实测量文本',
          fontSize: 20,
          fontFamily: 'Excalifont',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      )
      .addElement(
        ImageElement(
          id: ElementId('img-1'),
          x: 30,
          y: 80,
          width: 20,
          height: 20,
          fileId: 'file-1',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      );
  if (withImageFile) {
    scene = scene.addFile(
      'file-1',
      ImageFile(mimeType: 'image/png', bytes: onePixelPng),
    );
  }
  return scene;
}

/// golden 场景：形状 + 图片（确定性栅格，无字体渲染差异）。
Scene buildGoldenScene() => buildTestScene().removeElement(ElementId('text-1'));

/// 与渲染器同路径的真实文本测量（对照 oracle）。
TextMeasureResult measureTestText() => TextMeasureAdapter().measure(
  text: '真实测量文本',
  fontFamily: 'Excalifont',
  fontSize: 20,
  lineHeight: 1.25,
  maxWidth: 200,
);
