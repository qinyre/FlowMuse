class RoomCollaborator {
  const RoomCollaborator({
    required this.socketId,
    required this.username,
    required this.isGuest,
    this.role = '',
    this.userId,
    this.avatarUrl = '',
  });

  final String socketId;
  final String username;
  final bool isGuest;
  final String role;
  final String? userId;
  final String avatarUrl;

  factory RoomCollaborator.fromSocketId(String socketId) {
    return RoomCollaborator(socketId: socketId, username: '', isGuest: true);
  }

  factory RoomCollaborator.fromJson(Map<String, Object?> json) {
    return RoomCollaborator(
      socketId: json['socketId']! as String,
      username: json['username'] as String? ?? '',
      isGuest: json['isGuest'] as bool? ?? false,
      role: json['role'] as String? ?? '',
      userId: json['userId'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? '',
    );
  }
}
