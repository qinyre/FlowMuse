import 'package:flutter_dotenv/flutter_dotenv.dart';

class CollaborationConfig {
  const CollaborationConfig({required this.serverUrl});

  static CollaborationConfig get fromEnvironment {
    const dartDefinedServerUrl = String.fromEnvironment(
      'FLOWMUSE_COLLAB_SERVER_URL',
    );
    final dotenvServerUrl = dotenv.maybeGet('FLOWMUSE_COLLAB_SERVER_URL');
    return CollaborationConfig(
      serverUrl: dartDefinedServerUrl.isNotEmpty
          ? dartDefinedServerUrl
          : dotenvServerUrl ?? 'http://127.0.0.1:3000',
    );
  }

  final String serverUrl;
}
