import 'package:shared_preferences/shared_preferences.dart';

import '../collaboration/models/excalidraw_scene.dart';

abstract interface class WhiteboardSceneRepository {
  Future<String> loadScene(String notebookId);

  Future<void> saveScene(String notebookId, String content);
}

class InMemoryWhiteboardSceneRepository implements WhiteboardSceneRepository {
  final Map<String, String> _scenes = {};

  @override
  Future<String> loadScene(String notebookId) async {
    return _scenes[notebookId] ?? emptyExcalidrawSceneContent;
  }

  @override
  Future<void> saveScene(String notebookId, String content) async {
    _scenes[notebookId] = content;
  }
}

class SharedPreferencesWhiteboardSceneRepository
    implements WhiteboardSceneRepository {
  SharedPreferencesWhiteboardSceneRepository(
    Future<SharedPreferences> Function() preferences,
  ) : _preferences = preferences;

  SharedPreferencesWhiteboardSceneRepository.value(
    SharedPreferences preferences,
  ) : _preferences = (() async => preferences);

  static const _keyPrefix = 'whiteboard.excalidraw.scene.';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<String> loadScene(String notebookId) async {
    final preferences = await _preferences();
    final raw = preferences.getString('$_keyPrefix$notebookId');
    if (raw == null || raw.isEmpty) {
      return emptyExcalidrawSceneContent;
    }
    return raw;
  }

  @override
  Future<void> saveScene(String notebookId, String content) async {
    final preferences = await _preferences();
    await preferences.setString('$_keyPrefix$notebookId', content);
  }
}
