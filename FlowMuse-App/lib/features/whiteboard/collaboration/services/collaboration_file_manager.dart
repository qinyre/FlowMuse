import '../../editor_core/flow_muse_whiteboard_editor.dart' show ImageFile;
import 'collaboration_debug_log.dart';
import 'collaboration_file_store.dart';

class CollaborationFileManager {
  final Map<String, int> _savedFiles = {};

  Future<void> saveFiles({
    required CollaborationFileStore? fileStore,
    required String roomId,
    required String roomKey,
    required List<Map<String, Object?>> elements,
    required Map<String, Object?> filesJson,
    required List<String> priority,
    required bool Function() isCurrent,
    required void Function(CollaborationFileSaveResult) onFileSettled,
  }) async {
    if (fileStore == null) return;

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
      if (_savedFiles[fileId] == _fileVersion(fileJson)) {
        continue;
      }
      addedFiles[fileId] = fileJson;
    }

    for (final fileId in {...priority, ...addedFiles.keys}) {
      if (!isCurrent()) return;
      final file = addedFiles[fileId];
      if (file == null) continue;
      final result = await fileStore.uploadFiles(
        roomId: roomId,
        roomKey: roomKey,
        filesJson: {fileId: file},
        fileIds: [fileId],
      );
      if (!isCurrent()) return;
      final saved = result.savedFiles.containsKey(fileId);
      if (saved) _savedFiles[fileId] = _fileVersion(file);
      onFileSettled(
        CollaborationFileSaveResult(
          savedFileIds: saved ? {fileId} : const {},
          erroredFileIds: saved ? const {} : {fileId},
        ),
      );
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
    CollaborationDebugLog.write('file_manager', 'fetch_enqueue', {
      'room': _shortRoomId(roomId),
      'files': ids.map(_shortFileId).toList(),
    });
    final result = await fileStore.loadFiles(
      roomId: roomId,
      roomKey: roomKey,
      fileIds: ids,
    );
    for (final fileId in result.loadedFiles.keys) {
      _savedFiles[fileId] = 1;
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
  }

  int _fileVersion(Map<String, Object?> fileJson) {
    return (fileJson['version'] as num?)?.toInt() ?? 1;
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
