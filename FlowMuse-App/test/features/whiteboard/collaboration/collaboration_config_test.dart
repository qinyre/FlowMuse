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
    expect(config.shareOrigin, CollaborationConfig.defaultShareOrigin);
    expect(config.hasConfiguredShareOrigin, isTrue);
  });

  test('随包环境配置使用 HTTPS 生产后端', () async {
    await dotenv.load(fileName: 'assets/config/app.env');

    expect(
      CollaborationConfig.fromEnvironment.serverUrl,
      CollaborationConfig.productionServerUrl,
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
}
