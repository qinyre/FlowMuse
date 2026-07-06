import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../collaboration/models/collaborative_element.dart';
import '../collaboration/models/collaboration_room.dart';
import '../collaboration/repositories/collaboration_repository.dart';
import '../models/fractional_index.dart';
import '../models/whiteboard_element.dart';
import '../models/whiteboard_scene.dart';
import '../repositories/whiteboard_scene_repository.dart';

enum WhiteboardTool {
  hand,
  select,
  rectangle,
  ellipse,
  arrow,
  pen,
  text,
  image,
}

enum WhiteboardSaveStatus { idle, saving, saved }

class WhiteboardState {
  const WhiteboardState({
    this.notebookId = '',
    this.title = '未命名白板',
    this.elements = const [],
    this.activeTool = WhiteboardTool.select,
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
    this.saveStatus = WhiteboardSaveStatus.idle,
    this.canUndo = false,
    this.canRedo = false,
    this.activeRoom,
    this.collaborating = false,
  });

  final String notebookId;
  final String title;
  final List<WhiteboardElement> elements;
  final WhiteboardTool activeTool;
  final double zoom;
  final double panX;
  final double panY;
  final WhiteboardSaveStatus saveStatus;
  final bool canUndo;
  final bool canRedo;
  final CollaborationRoom? activeRoom;
  final bool collaborating;

  WhiteboardScene get scene {
    return WhiteboardScene(
      elements: elements,
      zoom: zoom,
      panX: panX,
      panY: panY,
    );
  }

  List<CollaborativeElement> get collaborativeElements {
    return [
      for (final element in elements) CollaborativeElement.fromElement(element),
    ];
  }

  String? get roomLink {
    final room = activeRoom;
    if (room == null) {
      return null;
    }
    return room.toLink(origin: 'https://flowmuse.local', path: '/whiteboard');
  }

  WhiteboardState copyWith({
    String? notebookId,
    String? title,
    List<WhiteboardElement>? elements,
    WhiteboardTool? activeTool,
    double? zoom,
    double? panX,
    double? panY,
    WhiteboardSaveStatus? saveStatus,
    bool? canUndo,
    bool? canRedo,
    CollaborationRoom? activeRoom,
    bool? collaborating,
    bool clearRoom = false,
  }) {
    return WhiteboardState(
      notebookId: notebookId ?? this.notebookId,
      title: title ?? this.title,
      elements: elements ?? this.elements,
      activeTool: activeTool ?? this.activeTool,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      saveStatus: saveStatus ?? this.saveStatus,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      activeRoom: clearRoom ? null : activeRoom ?? this.activeRoom,
      collaborating: collaborating ?? this.collaborating,
    );
  }
}

class WhiteboardViewModel extends Notifier<WhiteboardState> {
  late final CollaborationRepository _repository;
  late final WhiteboardSceneRepository _sceneRepository;
  final List<WhiteboardScene> _undoStack = [];
  final List<WhiteboardScene> _redoStack = [];
  int _nextElementNumber = 0;

  @override
  WhiteboardState build() {
    _repository = ref.watch(collaborationRepositoryProvider);
    _sceneRepository = ref.watch(whiteboardSceneRepositoryProvider);
    return const WhiteboardState();
  }

  Future<void> openNotebook({
    required String notebookId,
    required String title,
  }) async {
    final scene = await _sceneRepository.loadScene(notebookId);
    _undoStack.clear();
    _redoStack.clear();
    _nextElementNumber = scene.elements.length;
    state = state.copyWith(
      notebookId: notebookId,
      title: title,
      elements: scene.elements,
      zoom: scene.zoom,
      panX: scene.panX,
      panY: scene.panY,
      saveStatus: WhiteboardSaveStatus.saved,
      canUndo: false,
      canRedo: false,
    );
  }

  void selectTool(WhiteboardTool tool) {
    state = state.copyWith(activeTool: tool);
  }

  Future<void> addElement(WhiteboardElement element) async {
    _pushUndo();
    state = state.copyWith(
      elements: [...state.elements, element],
      saveStatus: WhiteboardSaveStatus.saving,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
    await _saveCurrentScene();
  }

  Future<void> addElementFromDrag({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    final element = _elementForDrag(
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
    );
    if (element == null) {
      return;
    }
    await addElement(element);
  }

  Future<void> zoomIn() async {
    state = state.copyWith(zoom: (state.zoom + 0.1).clamp(0.2, 4.0).toDouble());
    await _saveCurrentScene();
  }

  Future<void> zoomOut() async {
    state = state.copyWith(zoom: (state.zoom - 0.1).clamp(0.2, 4.0).toDouble());
    await _saveCurrentScene();
  }

  Future<void> resetZoom() async {
    state = state.copyWith(zoom: 1);
    await _saveCurrentScene();
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(state.scene);
    final scene = _undoStack.removeLast();
    state = state.copyWith(
      elements: scene.elements,
      zoom: scene.zoom,
      panX: scene.panX,
      panY: scene.panY,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
    await _saveCurrentScene();
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(state.scene);
    final scene = _redoStack.removeLast();
    state = state.copyWith(
      elements: scene.elements,
      zoom: scene.zoom,
      panX: scene.panX,
      panY: scene.panY,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
    await _saveCurrentScene();
  }

  Future<void> startCollaboration() async {
    final room = await _repository.startNewRoom(
      initialElements: state.collaborativeElements,
    );
    state = state.copyWith(activeRoom: room, collaborating: true);
  }

  Future<void> stopCollaboration() async {
    await _repository.stop();
    state = state.copyWith(collaborating: false, clearRoom: true);
  }

  WhiteboardElement? _elementForDrag({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) {
    final index = _nextFractionalIndex();
    final id =
        'element-${DateTime.now().microsecondsSinceEpoch}-$_nextElementNumber';
    final left = startX < endX ? startX : endX;
    final top = startY < endY ? startY : endY;
    final width = (endX - startX).abs();
    final height = (endY - startY).abs();
    if (width < 2 && height < 2 && state.activeTool != WhiteboardTool.text) {
      return null;
    }
    return switch (state.activeTool) {
      WhiteboardTool.rectangle => WhiteboardElement.rectangle(
        id: id,
        x: left,
        y: top,
        width: width,
        height: height,
        fractionalIndex: index,
      ),
      WhiteboardTool.ellipse => WhiteboardElement.ellipse(
        id: id,
        x: left,
        y: top,
        width: width,
        height: height,
        fractionalIndex: index,
      ),
      WhiteboardTool.arrow => WhiteboardElement.arrow(
        id: id,
        x1: startX,
        y1: startY,
        x2: endX,
        y2: endY,
        fractionalIndex: index,
      ),
      WhiteboardTool.pen => WhiteboardElement.path(
        id: id,
        points: [WhiteboardPoint(startX, startY), WhiteboardPoint(endX, endY)],
        fractionalIndex: index,
      ),
      WhiteboardTool.text => WhiteboardElement.text(
        id: id,
        x: startX,
        y: startY,
        text: '文本',
        fractionalIndex: index,
      ),
      _ => null,
    };
  }

  String _nextFractionalIndex() {
    _nextElementNumber += 1;
    final lastIndex = state.elements.isEmpty
        ? null
        : state.elements.last.fractionalIndex;
    return generateKeyBetween(lastIndex, null);
  }

  void _pushUndo() {
    _undoStack.add(state.scene);
    _redoStack.clear();
  }

  Future<void> _saveCurrentScene() async {
    if (state.notebookId.isEmpty) {
      return;
    }
    await _sceneRepository.saveScene(state.notebookId, state.scene);
    state = state.copyWith(
      saveStatus: WhiteboardSaveStatus.saved,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }
}

final collaborationRepositoryProvider = Provider<CollaborationRepository>((
  ref,
) {
  return CollaborationRepository();
});

final whiteboardSceneRepositoryProvider = Provider<WhiteboardSceneRepository>((
  ref,
) {
  return SharedPreferencesWhiteboardSceneRepository(
    SharedPreferences.getInstance,
  );
});

final whiteboardViewModelProvider =
    NotifierProvider<WhiteboardViewModel, WhiteboardState>(
      WhiteboardViewModel.new,
    );
