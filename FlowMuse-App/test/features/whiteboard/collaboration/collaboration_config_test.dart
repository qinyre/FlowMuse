import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(dotenv.clean);

  test('环境文件未初始化时使用内置默认配置', () {
    dotenv.clean();

    final config = CollaborationConfig.fromEnvironment;

    expect(config.serverUrl, 'https://api.flowmuse.cloud');
    expect(config.serverUrl, CollaborationConfig.productionServerUrl);
    expect(config.shareOrigin, 'https://app.flowmuse.cloud');
    expect(config.hasConfiguredShareOrigin, isTrue);
  });

  test('随包环境配置使用 HTTPS 生产后端', () async {
    await dotenv.load(fileName: 'assets/config/app.env');

    expect(
      CollaborationConfig.fromEnvironment.serverUrl,
      CollaborationConfig.productionServerUrl,
    );
    expect(
      CollaborationConfig.fromEnvironment.shareOrigin,
      CollaborationConfig.defaultShareOrigin,
    );
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

  test('空白配置回退生产值且局域网覆盖仍然可用', () {
    dotenv.loadFromString(
      envString: '''
FLOWMUSE_COLLAB_SERVER_URL="   "
FLOWMUSE_SHARE_ORIGIN=
''',
    );
    expect(
      CollaborationConfig.fromEnvironment.serverUrl,
      CollaborationConfig.productionServerUrl,
    );
    expect(
      CollaborationConfig.fromEnvironment.shareOrigin,
      CollaborationConfig.defaultShareOrigin,
    );

    dotenv.loadFromString(
      envString: '''
FLOWMUSE_COLLAB_SERVER_URL=" http://192.168.1.5:48931 "
FLOWMUSE_SHARE_ORIGIN=" http://192.168.1.5:8080/ "
''',
    );
    expect(
      CollaborationConfig.fromEnvironment.serverUrl,
      'http://192.168.1.5:48931',
    );
    expect(
      CollaborationConfig.fromEnvironment.shareOrigin,
      'http://192.168.1.5:8080/',
    );
  });
}
