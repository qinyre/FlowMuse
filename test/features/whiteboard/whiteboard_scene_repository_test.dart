import 'package:flow_muse/features/whiteboard/models/whiteboard_element.dart';
import 'package:flow_muse/features/whiteboard/models/whiteboard_scene.dart';
import 'package:flow_muse/features/whiteboard/repositories/whiteboard_scene_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves and loads scenes by notebook id', () async {
    final repository = InMemoryWhiteboardSceneRepository();
    final scene = WhiteboardScene(
      elements: [
        WhiteboardElement.rectangle(
          id: 'rect-1',
          x: 10,
          y: 20,
          width: 120,
          height: 80,
          fractionalIndex: 'a0',
        ),
      ],
    );

    await repository.saveScene('notebook-a', scene);

    final loaded = await repository.loadScene('notebook-a');
    expect(loaded.elements.single.id, 'rect-1');
    expect(loaded.elements.single.data['width'], 120);
  });

  test('keeps scenes isolated per notebook id', () async {
    final repository = InMemoryWhiteboardSceneRepository();

    await repository.saveScene(
      'notebook-a',
      WhiteboardScene(
        elements: [
          WhiteboardElement.rectangle(
            id: 'a',
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            fractionalIndex: 'a0',
          ),
        ],
      ),
    );

    final missing = await repository.loadScene('notebook-b');

    expect(missing.elements, isEmpty);
  });

  test('round trips scene json without losing element versions', () {
    final scene = WhiteboardScene(
      zoom: 1.25,
      panX: 12,
      panY: -8,
      elements: [
        WhiteboardElement.path(
          id: 'path-1',
          points: const [WhiteboardPoint(0, 0), WhiteboardPoint(10, 6)],
          fractionalIndex: 'a0',
          version: 3,
          versionNonce: 9,
        ),
      ],
    );

    final restored = WhiteboardScene.fromJson(scene.toJson());

    expect(restored.zoom, 1.25);
    expect(restored.panX, 12);
    expect(restored.elements.single.version, 3);
    expect(restored.elements.single.versionNonce, 9);
  });

  test('serializes scenes with Excalidraw-compatible shape', () {
    final scene = WhiteboardScene(
      zoom: 1.25,
      panX: 12,
      panY: -8,
      elements: [
        WhiteboardElement.rectangle(
          id: 'rect-1',
          x: 10,
          y: 20,
          width: 120,
          height: 80,
          fractionalIndex: 'a0',
          version: 3,
          versionNonce: 9,
          updatedAt: 1000,
        ),
      ],
    );

    final json = scene.toJson();
    final element = (json['elements']! as List).single as Map<String, Object?>;
    final appState = json['appState']! as Map<String, Object?>;

    expect(json['type'], 'excalidraw');
    expect(json['version'], 2);
    expect(json['source'], 'flowmuse');
    expect(json['files'], <String, Object?>{});
    expect(element['index'], 'a0');
    expect(element['updated'], 1000);
    expect(element['strokeColor'], '#1e1e1e');
    expect(element['backgroundColor'], 'transparent');
    expect(element['roughness'], 0);
    expect(element['groupIds'], <Object?>[]);
    expect(appState['scrollX'], -12);
    expect(appState['scrollY'], 8);
    expect(appState['zoom'], {'value': 1.25});
  });

  test('preserves Excalidraw appState fields while updating viewport fields', () {
    final scene = WhiteboardScene.fromJson({
      'type': 'excalidraw',
      'version': 2,
      'source': 'https://excalidraw.com',
      'elements': <Object?>[],
      'appState': {
        'theme': 'dark',
        'viewBackgroundColor': '#ffffff',
        'currentItemStrokeColor': '#ff0000',
        'gridSize': 20,
        'scrollX': -40,
        'scrollY': 12,
        'zoom': {'value': 2},
      },
      'files': {
        'file-1': {'mimeType': 'image/png'},
      },
    });

    final json = scene.copyWith(zoom: 1.5, panX: 8, panY: -6).toJson();
    final appState = json['appState']! as Map<String, Object?>;

    expect(json['source'], 'https://excalidraw.com');
    expect(appState['theme'], 'dark');
    expect(appState['viewBackgroundColor'], '#ffffff');
    expect(appState['currentItemStrokeColor'], '#ff0000');
    expect(appState['gridSize'], 20);
    expect(appState['scrollX'], -8);
    expect(appState['scrollY'], 6);
    expect(appState['zoom'], {'value': 1.5});
    expect(json['files'], {
      'file-1': {'mimeType': 'image/png'},
    });
  });

  test('persists scenes through shared preferences storage', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesWhiteboardSceneRepository.value(
      preferences,
    );

    await repository.saveScene(
      'notebook-a',
      WhiteboardScene(
        zoom: 1.5,
        elements: [
          WhiteboardElement.text(
            id: 'text-1',
            x: 24,
            y: 36,
            text: '课程结构',
            fractionalIndex: 'a0',
          ),
        ],
      ),
    );

    final restored = await SharedPreferencesWhiteboardSceneRepository.value(
      preferences,
    ).loadScene('notebook-a');

    expect(restored.zoom, 1.5);
    expect(restored.elements.single.id, 'text-1');
    expect(restored.elements.single.data['text'], '课程结构');
  });
}
