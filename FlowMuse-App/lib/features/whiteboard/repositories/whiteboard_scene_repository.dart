import 'package:shared_preferences/shared_preferences.dart';

import '../collaboration/models/excalidraw_scene.dart';

abstract interface class WhiteboardSceneRepository {
  Future<String> loadScene(String noteId);

  Future<void> saveScene(String noteId, String content);
}

class InMemoryWhiteboardSceneRepository implements WhiteboardSceneRepository {
  final Map<String, String> _scenes = {};

  @override
  Future<String> loadScene(String noteId) async {
    return _scenes[noteId] ?? emptyExcalidrawSceneContent;
  }

  @override
  Future<void> saveScene(String noteId, String content) async {
    _scenes[noteId] = content;
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

  static const _keyPrefix = 'note.excalidraw.scene.';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<String> loadScene(String noteId) async {
    final preferences = await _preferences();
    final raw = preferences.getString('$_keyPrefix$noteId');
    if (raw == null || raw.isEmpty) {
      return emptyExcalidrawSceneContent;
    }
    return raw;
  }

  @override
  Future<void> saveScene(String noteId, String content) async {
    final preferences = await _preferences();
    await preferences.setString('$_keyPrefix$noteId', content);
  }
}
