import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';

const int sceneFixtureSchemaVersion = 1;
const int sceneFixtureSeed = 1701;
const List<int> supportedSceneFixtureCounts = [100, 1000, 5000];

ExcalidrawScene buildSceneFixture(int count) {
  if (!supportedSceneFixtureCounts.contains(count)) {
    throw ArgumentError.value(count, 'count', 'unsupported fixture size');
  }
  return ExcalidrawScene(
    elements: [for (var index = 0; index < count; index++) _element(index)],
    appState: const {'viewBackgroundColor': '#ffffff'},
    files: const {},
    source: 'flowmuse://writing-performance-fixture/v1',
  );
}

Map<String, Object?> _element(int ordinal) {
  final typeIndex = ordinal % 4;
  final type = switch (typeIndex) {
    0 => 'freedraw',
    1 => 'rectangle',
    2 => 'text',
    _ => 'image',
  };
  final x = (ordinal % 50) * 36.0;
  final y = (ordinal ~/ 50) * 28.0;
  final base = <String, Object?>{
    'id': 'fixture-$ordinal',
    'type': type,
    'x': x,
    'y': y,
    'width': type == 'text' ? 96.0 : 24.0,
    'height': type == 'text' ? 24.0 : 20.0,
    'angle': 0.0,
    'strokeColor': '#1e1e1e',
    'backgroundColor': type == 'rectangle' ? '#dbeafe' : 'transparent',
    'fillStyle': 'solid',
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'roughness': 1.0,
    'opacity': 100,
    'groupIds': <String>[],
    'frameId': null,
    'index': 'a${ordinal.toString().padLeft(6, '0')}',
    'roundness': null,
    'seed': sceneFixtureSeed + ordinal,
    'version': 1,
    'versionNonce': sceneFixtureSeed * 10000 + ordinal,
    'isDeleted': false,
    'boundElements': <Object?>[],
    'updated': 1700000000000 + ordinal,
    'link': null,
    'locked': false,
  };
  switch (type) {
    case 'freedraw':
      base.addAll({
        'points': const [
          [0.0, 0.0],
          [8.0, 5.0],
          [16.0, -2.0],
          [24.0, 4.0],
        ],
        'pressures': const [0.3, 0.45, 0.6, 0.5],
        'simulatePressure': false,
        'lastCommittedPoint': null,
      });
      break;
    case 'text':
      base.addAll({
        'text': 'Fixture $ordinal',
        'originalText': 'Fixture $ordinal',
        'fontSize': 20.0,
        'fontFamily': 1,
        'textAlign': 'left',
        'verticalAlign': 'top',
        'containerId': null,
        'lineHeight': 1.25,
        'autoResize': true,
      });
      break;
    case 'image':
      base.addAll({
        'fileId': 'fixture-image-placeholder',
        'status': 'pending',
        'scale': const [1, 1],
        'crop': null,
      });
      break;
    case 'rectangle':
      break;
  }
  return base;
}
