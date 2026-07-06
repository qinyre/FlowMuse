import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collaboration/models/collaborative_element.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/repositories/collaboration_repository.dart';

class WhiteboardState {
  const WhiteboardState({
    this.elements = const [],
    this.activeRoom,
    this.collaborating = false,
  });

  final List<CollaborativeElement> elements;
  final CollaborationRoom? activeRoom;
  final bool collaborating;

  String? get roomLink {
    final room = activeRoom;
    if (room == null) {
      return null;
    }
    return room.toLink(origin: 'https://flowmuse.local', path: '/whiteboard');
  }

  WhiteboardState copyWith({
    List<CollaborativeElement>? elements,
    CollaborationRoom? activeRoom,
    bool? collaborating,
    bool clearRoom = false,
  }) {
    return WhiteboardState(
      elements: elements ?? this.elements,
      activeRoom: clearRoom ? null : activeRoom ?? this.activeRoom,
      collaborating: collaborating ?? this.collaborating,
    );
  }
}

class WhiteboardViewModel extends Notifier<WhiteboardState> {
  late final CollaborationRepository _repository;

  @override
  WhiteboardState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    return const WhiteboardState();
  }

  Future<void> startCollaboration() async {
    final room = await _repository.startNewRoom(
      initialElements: state.elements,
    );
    state = state.copyWith(activeRoom: room, collaborating: true);
  }

  Future<void> stopCollaboration() async {
    await _repository.stop();
    state = state.copyWith(collaborating: false, clearRoom: true);
  }
}

final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  return CollaborationRepository();
});

final whiteboardViewModelProvider =
    NotifierProvider<WhiteboardViewModel, WhiteboardState>(
      WhiteboardViewModel.new,
    );
