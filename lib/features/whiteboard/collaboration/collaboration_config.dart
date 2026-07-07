class CollaborationConfig {
  const CollaborationConfig({required this.serverUrl});

  static const fromEnvironment = CollaborationConfig(
    serverUrl: String.fromEnvironment(
      'FLOWMUSE_COLLAB_SERVER_URL',
      defaultValue: 'http://127.0.0.1:3000',
    ),
  );

  final String serverUrl;
}
