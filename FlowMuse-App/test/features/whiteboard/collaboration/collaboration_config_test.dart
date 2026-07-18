import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(dotenv.clean);

  test('环境文件未初始化时使用安全默认配置', () {
    dotenv.clean();

    final config = CollaborationConfig.fromEnvironment;

    expect(config.serverUrl, CollaborationConfig.defaultServerUrl);
    expect(config.shareOrigin, CollaborationConfig.defaultShareOrigin);
  });

  test('环境文件已初始化时读取协作配置', () {
    dotenv.loadFromString(
      envString: '''
FLOWMUSE_COLLAB_SERVER_URL=https://collab.example.com
FLOWMUSE_SHARE_ORIGIN=https://share.example.com
''',
    );

    final config = CollaborationConfig.fromEnvironment;

    expect(config.serverUrl, 'https://collab.example.com');
    expect(config.shareOrigin, 'https://share.example.com');
  });
}
