enum CollaboratorIdleState { active, idle, away }

class CollaboratorPresence {
  const CollaboratorPresence({
    required this.socketId,
    this.username = '',
    this.pointer,
    this.button = 'up',
    this.selectedElementIds = const {},
    this.idleState = CollaboratorIdleState.active,
    this.isCurrentUser = false,
  });

  final String socketId;
  final String username;
  final Map<String, Object?>? pointer;
  final String button;
  final Map<String, bool> selectedElementIds;
  final CollaboratorIdleState idleState;
  final bool isCurrentUser;

  CollaboratorPresence copyWith({
    String? username,
    Map<String, Object?>? pointer,
    String? button,
    Map<String, bool>? selectedElementIds,
    CollaboratorIdleState? idleState,
    bool? isCurrentUser,
  }) {
    return CollaboratorPresence(
      socketId: socketId,
      username: username ?? this.username,
      pointer: pointer ?? this.pointer,
      button: button ?? this.button,
      selectedElementIds: selectedElementIds ?? this.selectedElementIds,
      idleState: idleState ?? this.idleState,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }
}
