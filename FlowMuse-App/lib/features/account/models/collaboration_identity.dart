import 'account_user.dart';

class CollaborationIdentity {
  const CollaborationIdentity({
    required this.username,
    required this.isGuest,
    this.userId,
    this.avatarUrl = '',
    this.token,
  });

  final String username;
  final bool isGuest;
  final String? userId;
  final String avatarUrl;
  final String? token;

  factory CollaborationIdentity.fromUser(AccountUser user, String token) {
    return CollaborationIdentity(
      username: user.collaboratorName,
      isGuest: false,
      userId: user.id,
      avatarUrl: user.avatarUrl,
      token: token,
    );
  }

  static CollaborationIdentity guest(String username, {String avatarUrl = ''}) {
    return CollaborationIdentity(
      username: username,
      isGuest: true,
      avatarUrl: avatarUrl,
    );
  }
}
