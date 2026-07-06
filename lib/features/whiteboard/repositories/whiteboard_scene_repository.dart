import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/whiteboard_scene.dart';

abstract interface class WhiteboardSceneRepository {
  Future<WhiteboardScene> loadScene(String notebookId);

  Future<void> saveScene(String notebookId, WhiteboardScene scene);
}

class InMemoryWhiteboardSceneRepository implements WhiteboardSceneRepository {
  final Map<String, WhiteboardScene> _scenes = {};

  @override
  Future<WhiteboardScene> loadScene(String notebookId) async {
    return _scenes[notebookId] ?? const WhiteboardScene();
  }

  @override
  Future<void> saveScene(String notebookId, WhiteboardScene scene) async {
    _scenes[notebookId] = scene;
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

  static const _keyPrefix = 'whiteboard.scene.';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<WhiteboardScene> loadScene(String notebookId) async {
    final preferences = await _preferences();
    final raw = preferences.getString('$_keyPrefix$notebookId');
    if (raw == null || raw.isEmpty) {
      return const WhiteboardScene();
    }
    final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
    return WhiteboardScene.fromJson(json);
  }

  @override
  Future<void> saveScene(String notebookId, WhiteboardScene scene) async {
    final preferences = await _preferences();
    await preferences.setString(
      '$_keyPrefix$notebookId',
      jsonEncode(scene.toJson()),
    );
  }
}
