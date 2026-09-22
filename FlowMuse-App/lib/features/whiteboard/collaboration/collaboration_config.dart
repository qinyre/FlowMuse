import 'package:flutter_dotenv/flutter_dotenv.dart';

class CollaborationConfig {
  const CollaborationConfig({
    required this.serverUrl,
    required this.shareOrigin,
  });

  static const String productionServerUrl = 'https://api.flowmuse.cloud';
  static const String defaultServerUrl = productionServerUrl;
  static const String defaultShareOrigin = 'https://app.flowmuse.cloud';

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
      serverUrl: _configuredUrl(
        dartDefinedServerUrl,
        dotenvServerUrl,
        defaultServerUrl,
      ),
      shareOrigin: _configuredUrl(
        dartDefinedShareOrigin,
        dotenvShareOrigin,
        defaultShareOrigin,
      ),
    );
  }

  final String serverUrl;
  final String shareOrigin;

  bool get hasConfiguredShareOrigin =>
      shareOrigin.isNotEmpty && shareOrigin != 'https://flowmuse.local';

  static String _configuredUrl(
    String defined,
    String? bundled,
    String fallback,
  ) {
    for (final value in [defined, bundled ?? '', fallback]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }
}
