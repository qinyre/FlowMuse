class SceneContentStore {
  SceneContentStore({this.rootPath});

  static const referencePrefix = '@scene-file:';

  final String? rootPath;

  bool isReference(String value) => value.startsWith(referencePrefix);

  Future<String> write(String noteId, String content) {
    throw UnsupportedError('当前平台不支持本地场景文件');
  }

  Future<String?> read(String reference) async => null;
}
