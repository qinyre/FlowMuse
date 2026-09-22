import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('游客头像使用固定版本的 HTTPS 跨域 CDN', () {
    const account = AccountState(guestName: '活泼袋鼠#TEST');
    expect(
      account.collaborationIdentity.avatarUrl,
      'https://cdn.jsdelivr.net/npm/openmoji@15.1.0/color/svg/1F998.svg',
    );
  });
}
