import 'package:flow_muse/features/whiteboard/models/whiteboard_element.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips Excalidraw text container fields', () {
    final element = WhiteboardElement.fromJson({
      'id': 'text-1',
      'type': 'text',
      'x': 10,
      'y': 12,
      'width': 80,
      'height': 32,
      'angle': 0,
      'strokeColor': '#1e1e1e',
      'backgroundColor': 'transparent',
      'fillStyle': 'solid',
      'strokeWidth': 2,
      'strokeStyle': 'solid',
      'roughness': 0,
      'opacity': 100,
      'seed': 1,
      'version': 4,
      'versionNonce': 5,
      'index': 'a0',
      'isDeleted': false,
      'groupIds': <String>[],
      'frameId': null,
      'boundElements': null,
      'updated': 1000,
      'link': null,
      'locked': false,
      'text': '节点',
      'fontSize': 20,
      'fontFamily': 1,
      'textAlign': 'center',
      'verticalAlign': 'middle',
      'containerId': 'rect-1',
      'originalText': '节点',
      'autoResize': false,
      'lineHeight': 1.25,
    });

    final json = element.toJson();

    expect(json['containerId'], 'rect-1');
    expect(json['originalText'], '节点');
    expect(json['autoResize'], false);
    expect(json['lineHeight'], 1.25);
  });

  test('round trips Excalidraw linear binding and arrowhead fields', () {
    final startBinding = {
      'elementId': 'rect-1',
      'focus': 0.2,
      'gap': 4,
      'fixedPoint': [0.5, 0.0],
      'mode': 'inside',
    };
    final element = WhiteboardElement.fromJson({
      'id': 'arrow-1',
      'type': 'arrow',
      'x': 10,
      'y': 20,
      'width': 100,
      'height': 50,
      'angle': 0,
      'strokeColor': '#1e1e1e',
      'backgroundColor': 'transparent',
      'fillStyle': 'solid',
      'strokeWidth': 2,
      'strokeStyle': 'solid',
      'roughness': 0,
      'opacity': 100,
      'seed': 1,
      'version': 4,
      'versionNonce': 5,
      'index': 'a0',
      'isDeleted': false,
      'groupIds': <String>[],
      'frameId': null,
      'boundElements': null,
      'updated': 1000,
      'link': null,
      'locked': false,
      'points': [
        [0, 0],
        [100, 50],
      ],
      'startBinding': startBinding,
      'endBinding': null,
      'startArrowhead': null,
      'endArrowhead': 'arrow',
      'elbowed': false,
    });

    final json = element.toJson();

    expect(json['startBinding'], startBinding);
    expect(json['endBinding'], isNull);
    expect(json['startArrowhead'], isNull);
    expect(json['endArrowhead'], 'arrow');
    expect(json['elbowed'], false);
  });

  test('round trips Excalidraw freedraw pressure fields', () {
    final element = WhiteboardElement.fromJson({
      'id': 'draw-1',
      'type': 'freedraw',
      'x': 10,
      'y': 20,
      'width': 12,
      'height': 8,
      'angle': 0,
      'strokeColor': '#1e1e1e',
      'backgroundColor': 'transparent',
      'fillStyle': 'solid',
      'strokeWidth': 2,
      'strokeStyle': 'solid',
      'roughness': 0,
      'opacity': 100,
      'seed': 1,
      'version': 4,
      'versionNonce': 5,
      'index': 'a0',
      'isDeleted': false,
      'groupIds': <String>[],
      'frameId': null,
      'boundElements': null,
      'updated': 1000,
      'link': null,
      'locked': false,
      'points': [
        [0, 0],
        [12, 8],
      ],
      'pressures': [0.1, 0.6],
      'simulatePressure': true,
      'strokeOptions': {'variability': 'constant', 'streamline': 0.5},
    });

    final json = element.toJson();

    expect(json['pressures'], [0.1, 0.6]);
    expect(json['simulatePressure'], true);
    expect(json['strokeOptions'], {
      'variability': 'constant',
      'streamline': 0.5,
    });
  });

  test('round trips Excalidraw frame name and embedded element types', () {
    final frame = WhiteboardElement.fromJson({
      'id': 'frame-1',
      'type': 'magicframe',
      'x': 0,
      'y': 0,
      'width': 320,
      'height': 240,
      'angle': 0,
      'strokeColor': '#1e1e1e',
      'backgroundColor': 'transparent',
      'fillStyle': 'solid',
      'strokeWidth': 2,
      'strokeStyle': 'solid',
      'roughness': 0,
      'opacity': 100,
      'seed': 1,
      'version': 4,
      'versionNonce': 5,
      'index': 'a0',
      'isDeleted': false,
      'groupIds': <String>[],
      'frameId': null,
      'boundElements': null,
      'updated': 1000,
      'link': null,
      'locked': false,
      'name': '流程',
    });

    expect(frame.type, WhiteboardElementType.magicFrame);
    expect(frame.toJson()['type'], 'magicframe');
    expect(frame.toJson()['name'], '流程');
  });

  test('rejects legacy nested data element json', () {
    expect(
      () => WhiteboardElement.fromJson({
        'id': 'legacy-1',
        'type': 'rectangle',
        'version': 1,
        'versionNonce': 2,
        'updated': 1000,
        'index': 'a0',
        'isDeleted': false,
        'data': {'x': 10, 'y': 20, 'width': 30, 'height': 40},
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
