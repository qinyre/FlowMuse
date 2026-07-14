class SceneContentStore {
  SceneContentStore({this.rootPath});

  static const referencePrefix = '@scene-file:';

  final String? rootPath;

  bool isReference(String value) => value.startsWith(referencePrefix);

  Future<String> write(String noteId, String content) async => content;

  Future<String?> read(String reference) async => null;
}
