import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/whiteboard_scene.dart';

const emptyExcalidrawSceneContent =
    '{"type":"excalidraw","version":2,"source":"https://excalidraw.com","elements":[],"appState":{},"files":{}}';

abstract interface class WhiteboardSceneRepository {
  Future<WhiteboardScene> loadScene(String notebookId);

  Future<void> saveScene(String notebookId, WhiteboardScene scene);

  Future<String> loadSceneContent(String notebookId);

  Future<void> saveSceneContent(String notebookId, String content);
}

class InMemoryWhiteboardSceneRepository implements WhiteboardSceneRepository {
  final Map<String, WhiteboardScene> _scenes = {};
  final Map<String, String> _sceneContents = {};

  @override
  Future<WhiteboardScene> loadScene(String notebookId) async {
    return _scenes[notebookId] ?? const WhiteboardScene();
  }

  @override
  Future<void> saveScene(String notebookId, WhiteboardScene scene) async {
    _scenes[notebookId] = scene;
  }

  @override
  Future<String> loadSceneContent(String notebookId) async {
    return _sceneContents[notebookId] ?? emptyExcalidrawSceneContent;
  }

  @override
  Future<void> saveSceneContent(String notebookId, String content) async {
    _sceneContents[notebookId] = content;
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
  static const _contentKeyPrefix = 'whiteboard.scene.content.';

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

  @override
  Future<String> loadSceneContent(String notebookId) async {
    final preferences = await _preferences();
    final raw = preferences.getString('$_contentKeyPrefix$notebookId');
    if (raw == null || raw.isEmpty) {
      return emptyExcalidrawSceneContent;
    }
    return raw;
  }

  @override
  Future<void> saveSceneContent(String notebookId, String content) async {
    final preferences = await _preferences();
    await preferences.setString('$_contentKeyPrefix$notebookId', content);
  }
}
