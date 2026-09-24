import 'package:flow_muse/features/account/repositories/account_repository.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('上传头像地址保留版本查询参数及服务前缀', () {
    // Given: 上传接口返回带缓存版本的相对头像 URL。
    const avatar = '/api/users/test-user/avatar?v=123&crop=center';
    for (final basePath in ['', '/', '/service', '/service/']) {
      final repository = AccountRepository(
        config: CollaborationConfig(
          serverUrl: 'https://api.flowmuse.example$basePath',
          shareOrigin: 'https://app.flowmuse.example',
        ),
      );
      addTearDown(repository.close);

      // When: 所有头像组件通过账户仓库解析服务器返回的 URL。
      final resolved = Uri.parse(repository.resolveAvatarUrl(avatar));

      // Then: query 不得成为 path 的一部分，自建服务前缀仍保留。
      final prefix = basePath.startsWith('/service') ? '/service' : '';
      expect(resolved.path, '$prefix/api/users/test-user/avatar');
      expect(resolved.queryParameters, {'v': '123', 'crop': 'center'});
      expect(resolved.origin, 'https://api.flowmuse.example');
      expect(repository.resolveAvatarUrl(''), '');
      const cdn = 'https://cdn.example/avatar.png?v=456';
      expect(repository.resolveAvatarUrl(cdn), cdn);
      expect(
        repository.resolveAvatarUrl('/api/users/test-user/avatar'),
        'https://api.flowmuse.example$prefix/api/users/test-user/avatar',
      );
    }
  });

  test('游客头像使用固定版本的 HTTPS 跨域 CDN', () {
    const account = AccountState(guestName: '活泼袋鼠#TEST');
    expect(
      account.collaborationIdentity.avatarUrl,
      'https://cdn.jsdelivr.net/npm/openmoji@15.1.0/color/svg/1F998.svg',
    );
  });
}
