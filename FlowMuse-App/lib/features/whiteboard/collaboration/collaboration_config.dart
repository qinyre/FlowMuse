import 'package:flutter_dotenv/flutter_dotenv.dart';

class CollaborationConfig {
  const CollaborationConfig({
    required this.serverUrl,
    required this.shareOrigin,
  });

  static const String defaultShareOrigin = 'https://flowmuse.local';

  static CollaborationConfig get fromEnvironment {
    const dartDefinedServerUrl = String.fromEnvironment(
      'FLOWMUSE_COLLAB_SERVER_URL',
    );
    const dartDefinedShareOrigin = String.fromEnvironment(
      'FLOWMUSE_SHARE_ORIGIN',
    );
    final dotenvServerUrl = dotenv.maybeGet('FLOWMUSE_COLLAB_SERVER_URL');
    final dotenvShareOrigin = dotenv.maybeGet('FLOWMUSE_SHARE_ORIGIN');
    return CollaborationConfig(
      serverUrl: dartDefinedServerUrl.isNotEmpty
          ? dartDefinedServerUrl
          : dotenvServerUrl ?? 'http://127.0.0.1:3000',
      shareOrigin: dartDefinedShareOrigin.isNotEmpty
          ? dartDefinedShareOrigin
          : dotenvShareOrigin ?? defaultShareOrigin,
    );
  }

  final String serverUrl;
  final String shareOrigin;

  bool get hasConfiguredShareOrigin => shareOrigin != defaultShareOrigin;
}
