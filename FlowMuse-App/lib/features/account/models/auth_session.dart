import 'account_user.dart';

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AccountUser user;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      token: json['token']! as String,
      user: AccountUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }
}
