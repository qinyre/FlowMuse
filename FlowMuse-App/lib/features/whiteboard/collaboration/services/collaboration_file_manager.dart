import '../../editor_core/flow_muse_whiteboard_editor.dart' show ImageFile;
import 'collaboration_debug_log.dart';
import 'collaboration_file_store.dart';

class CollaborationFileManager {
  final Map<String, bool> _fetchingFiles = {};
  final Map<String, bool> _erroredFilesFetch = {};
  final Map<String, int> _savingFiles = {};
  final Map<String, int> _savedFiles = {};
  final Map<String, int> _erroredFilesSave = {};

  bool isFileTracked(String id) {
    return _savedFiles.containsKey(id) ||
        _savingFiles.containsKey(id) ||
        _fetchingFiles.containsKey(id) ||
        _erroredFilesFetch.containsKey(id) ||
        _erroredFilesSave.containsKey(id);
  }

  Future<CollaborationFileSaveResult> saveFiles({
    required CollaborationFileStore? fileStore,
    required String roomId,
    required String roomKey,
    required List<Map<String, Object?>> elements,
    required Map<String, Object?> filesJson,
  }) async {
    if (fileStore == null) {
      return const CollaborationFileSaveResult(
        savedFileIds: {},
        erroredFileIds: {},
      );
    }

    final addedFiles = <String, Map<String, Object?>>{};
    for (final element in elements) {
      final fileId = _imageFileId(element);
      if (fileId == null) {
        continue;
      }
      final file = filesJson[fileId];
      if (file is! Map) {
        continue;
      }
      final fileJson = Map<String, Object?>.from(file);
      if (isFileSavedOrBeingSaved(fileId, fileJson)) {
        continue;
      }
      addedFiles[fileId] = fileJson;
      _savingFiles[fileId] = getFileVersion(fileJson);
    }

    if (addedFiles.isEmpty) {
      return const CollaborationFileSaveResult(
        savedFileIds: {},
        erroredFileIds: {},
      );
    }

    CollaborationDebugLog.write('file_manager', 'save_enqueue', {
      'room': _shortRoomId(roomId),
      'files': addedFiles.keys.map(_shortFileId).toList(),
    });
    try {
      final result = await fileStore.uploadFiles(
        roomId: roomId,
        roomKey: roomKey,
        filesJson: filesJson,
        fileIds: addedFiles.keys,
      );
      for (final entry in result.savedFiles.entries) {
        _savedFiles[entry.key] = getFileVersion(entry.value);
      }
      for (final entry in result.erroredFiles.entries) {
        _erroredFilesSave[entry.key] = getFileVersion(entry.value);
      }
      CollaborationDebugLog.write('file_manager', 'save_result', {
        'room': _shortRoomId(roomId),
        'saved': result.savedFiles.keys.map(_shortFileId).toList(),
        'errored': result.erroredFiles.keys.map(_shortFileId).toList(),
      });
      return CollaborationFileSaveResult(
        savedFileIds: result.savedFiles.keys.toSet(),
        erroredFileIds: result.erroredFiles.keys.toSet(),
      );
    } finally {
      for (final fileId in addedFiles.keys) {
        _savingFiles.remove(fileId);
      }
    }
  }

  Future<CollaborationFileFetchResult> getFiles({
    required CollaborationFileStore? fileStore,
    required String roomId,
    required String roomKey,
    required Iterable<String> fileIds,
  }) async {
    if (fileStore == null) {
      return const CollaborationFileFetchResult(
        loadedFiles: {},
        erroredFileIds: {},
      );
    }
    final ids = fileIds.toSet();
    if (ids.isEmpty) {
      return const CollaborationFileFetchResult(
        loadedFiles: {},
        erroredFileIds: {},
      );
    }
    for (final id in ids) {
      _fetchingFiles[id] = true;
    }
    CollaborationDebugLog.write('file_manager', 'fetch_enqueue', {
      'room': _shortRoomId(roomId),
      'files': ids.map(_shortFileId).toList(),
    });
    try {
      final result = await fileStore.loadFiles(
        roomId: roomId,
        roomKey: roomKey,
        fileIds: ids,
      );
      for (final fileId in result.loadedFiles.keys) {
        _savedFiles[fileId] = 1;
      }
      for (final fileId in result.erroredFileIds) {
        _erroredFilesFetch[fileId] = true;
      }
      CollaborationDebugLog.write('file_manager', 'fetch_result', {
        'room': _shortRoomId(roomId),
        'loaded': result.loadedFiles.keys.map(_shortFileId).toList(),
        'errored': result.erroredFileIds.map(_shortFileId).toList(),
      });
      return CollaborationFileFetchResult(
        loadedFiles: result.loadedFiles,
        erroredFileIds: result.erroredFileIds,
      );
    } finally {
      for (final id in ids) {
        _fetchingFiles.remove(id);
      }
    }
  }

  bool shouldUpdateImageElementStatus(Map<String, Object?> element) {
    final fileId = _imageFileId(element);
    return fileId != null &&
        _savedFiles.containsKey(fileId) &&
        element['status'] == 'pending';
  }

  bool isFileSavedOrBeingSaved(String fileId, Map<String, Object?> fileJson) {
    final fileVersion = getFileVersion(fileJson);
    return _savedFiles[fileId] == fileVersion ||
        _savingFiles[fileId] == fileVersion;
  }

  int getFileVersion(Map<String, Object?> fileJson) {
    return (fileJson['version'] as num?)?.toInt() ?? 1;
  }

  void reset() {
    CollaborationDebugLog.write('file_manager', 'reset', {
      'saving': _savingFiles.length,
      'saved': _savedFiles.length,
      'fetching': _fetchingFiles.length,
      'saveErrors': _erroredFilesSave.length,
      'fetchErrors': _erroredFilesFetch.length,
    });
    _fetchingFiles.clear();
    _savingFiles.clear();
    _savedFiles.clear();
    _erroredFilesFetch.clear();
    _erroredFilesSave.clear();
  }

  String? _imageFileId(Map<String, Object?> element) {
    if (element['type'] != 'image' || element['isDeleted'] == true) {
      return null;
    }
    final fileId = element['fileId'];
    return fileId is String && fileId.isNotEmpty ? fileId : null;
  }

  String _shortRoomId(String roomId) =>
      roomId.length > 8 ? roomId.substring(0, 8) : roomId;

  String _shortFileId(String fileId) =>
      fileId.length > 8 ? fileId.substring(0, 8) : fileId;
}

class CollaborationFileSaveResult {
  const CollaborationFileSaveResult({
    required this.savedFileIds,
    required this.erroredFileIds,
  });

  final Set<String> savedFileIds;
  final Set<String> erroredFileIds;
}

class CollaborationFileFetchResult {
  const CollaborationFileFetchResult({
    required this.loadedFiles,
    required this.erroredFileIds,
  });

  final Map<String, ImageFile> loadedFiles;
  final Set<String> erroredFileIds;
}
