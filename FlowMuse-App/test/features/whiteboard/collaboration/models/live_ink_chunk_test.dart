import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';

void main() {
  const style = LiveInkStyle(
    brushType: 'fountainPen',
    strokeColor: '#123456',
    strokeWidth: 2,
    opacity: 100,
  );

  test('INK_CHUNK 使用现有大写包络 round-trip', () {
    final message = CollaborationMessage.inkChunk(
      const LiveInkChunk(
        strokeId: 'stroke-1',
        startIndex: 84,
        points: [LiveInkPoint(x: 1.2, y: 2.4, pressure: 0.6)],
        style: style,
      ),
    );

    final decoded = CollaborationMessage.fromBytes(message.toBytes());
    final chunk = decoded.liveInkChunk!;

    expect(decoded.type, CollaborationMessageType.inkChunk);
    expect(chunk.strokeId, 'stroke-1');
    expect(chunk.startIndex, 84);
    expect(chunk.points.single.pressure, 0.6);
    expect(chunk.style.brushType, 'fountainPen');
  });

  test('绝对 startIndex 恢复每个点索引', () {
    final chunk = LiveInkChunk.fromJson(_json(points: 3, startIndex: 7));
    expect(chunk.indexedPoints.map((item) => item.index), [7, 8, 9]);
  });

  test('重复与乱序包按绝对索引去重并保留显式缺口', () {
    final points = <int, LiveInkPoint>{};
    final later = LiveInkChunk.fromJson(_json(points: 2, startIndex: 3));
    final earlier = LiveInkChunk.fromJson(_json(points: 2, startIndex: 0));
    final duplicate = LiveInkChunk.fromJson(_json(points: 2, startIndex: 3));

    expect(later.addMissingPointsTo(points), 2);
    expect(earlier.addMissingPointsTo(points), 2);
    expect(duplicate.addMissingPointsTo(points), 0);
    expect(points.keys.toList()..sort(), [0, 1, 3, 4]);
    expect(points.containsKey(2), isFalse);
  });

  test('严格拒绝非法坐标、压力、索引、样式与包长', () {
    final invalid = <Map<String, Object?>>[
      _json()..['protocolVersion'] = 1,
      _json()..['strokeId'] = '',
      _json()..['strokeId'] = List.filled(43, '字').join(),
      _json()..['startIndex'] = -1,
      _json()..['startIndex'] = 1.5,
      _json()..['points'] = const [],
      _json(points: 65),
      _json()
        ..['points'] = [
          {'x': double.nan, 'y': 0, 'pressure': null},
        ],
      _json()
        ..['points'] = [
          {'x': double.infinity, 'y': 0, 'pressure': null},
        ],
      _json()
        ..['points'] = [
          {'x': 10000001, 'y': 0, 'pressure': null},
        ],
      _json()
        ..['points'] = [
          {'x': 0, 'y': 0, 'pressure': 1.1},
        ],
      _json()..remove('style'),
      _json()..['style'] = {...style.toJson(), 'brushType': 'unknown'},
      _json()..['style'] = {...style.toJson(), 'strokeColor': 'black'},
      _json()..['style'] = {...style.toJson(), 'strokeWidth': 0},
      _json()..['style'] = {...style.toJson(), 'opacity': 101},
    ];

    for (final json in invalid) {
      expect(() => LiveInkChunk.fromJson(json), throwsFormatException);
    }
  });

  test('64 点最大包加密后小于服务端 64KiB 外层边界且篡改失败', () async {
    final crypto = CollaborationCrypto();
    final roomKey = crypto.generateRoomKey();
    final message = CollaborationMessage.inkChunk(
      LiveInkChunk.fromJson(_json(points: 64)),
    );
    final encrypted = await crypto.encrypt(
      roomKey: roomKey,
      plainBytes: message.toBytes(),
    );

    expect(encrypted.encryptedBuffer.length, lessThanOrEqualTo(64 * 1024));
    final tampered = [...encrypted.encryptedBuffer]
      ..[0] = encrypted.encryptedBuffer.first ^ 1;
    await expectLater(
      crypto.decrypt(
        roomKey: roomKey,
        encryptedPayload: EncryptedPayload(
          encryptedBuffer: tampered,
          iv: encrypted.iv,
        ),
      ),
      throwsA(anything),
    );
  });
}

Map<String, Object?> _json({int points = 1, int startIndex = 0}) => {
  'protocolVersion': 2,
  'strokeId': 'stroke',
  'startIndex': startIndex,
  'points': [
    for (var index = 0; index < points; index++)
      {'x': index.toDouble(), 'y': index.toDouble(), 'pressure': 0.5},
  ],
  'style': const LiveInkStyle(
    brushType: 'fountainPen',
    strokeColor: '#123456',
    strokeWidth: 2,
    opacity: 100,
  ).toJson(),
};
