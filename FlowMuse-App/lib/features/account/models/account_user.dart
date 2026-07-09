class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl = '',
    this.registeredAt = 0,
    this.emailVerified = false,
    this.emailVerifiedAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String email;
  final String displayName;
  final String avatarUrl;
  final int registeredAt;
  final bool emailVerified;
  final int emailVerifiedAt;
  final int updatedAt;

  String get collaboratorName {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    return email;
  }

  factory AccountUser.fromJson(Map<String, Object?> json) {
    return AccountUser(
      id: json['id']! as String,
      email: json['email']! as String,
      displayName: json['displayName']! as String,
      avatarUrl: json['avatarUrl'] as String? ?? '',
      registeredAt: (json['registeredAt'] as num?)?.toInt() ?? 0,
      emailVerified: json['emailVerified'] as bool? ?? false,
      emailVerifiedAt: (json['emailVerifiedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
