import 'package:flutter_dotenv/flutter_dotenv.dart';

class CollaborationConfig {
  const CollaborationConfig({
    required this.serverUrl,
    required this.shareOrigin,
  });

  static const String defaultServerUrl = 'https://api.flowmuse.cloud';
  static const String defaultShareOrigin = 'https://qinyre.github.io/FlowMuse';

  static CollaborationConfig get fromEnvironment {
    const dartDefinedServerUrl = String.fromEnvironment(
      'FLOWMUSE_COLLAB_SERVER_URL',
    );
    const dartDefinedShareOrigin = String.fromEnvironment(
      'FLOWMUSE_SHARE_ORIGIN',
    );
    final dotenvServerUrl = dotenv.isInitialized
        ? dotenv.maybeGet('FLOWMUSE_COLLAB_SERVER_URL')
        : null;
    final dotenvShareOrigin = dotenv.isInitialized
        ? dotenv.maybeGet('FLOWMUSE_SHARE_ORIGIN')
        : null;
    return CollaborationConfig(
      serverUrl: dartDefinedServerUrl.isNotEmpty
          ? dartDefinedServerUrl
          : dotenvServerUrl ?? defaultServerUrl,
      shareOrigin: dartDefinedShareOrigin.isNotEmpty
          ? dartDefinedShareOrigin
          : dotenvShareOrigin ?? defaultShareOrigin,
    );
  }

  final String serverUrl;
  final String shareOrigin;

  bool get hasConfiguredShareOrigin =>
      shareOrigin.isNotEmpty && shareOrigin != 'https://flowmuse.local';
}
