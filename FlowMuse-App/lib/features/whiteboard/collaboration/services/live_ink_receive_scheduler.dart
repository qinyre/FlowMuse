import 'dart:async';
import 'dart:collection';

import '../models/live_ink_chunk.dart';
import '../models/received_live_ink_frame.dart';

typedef LiveInkFrameDecoder =
    Future<LiveInkChunk> Function(ReceivedLiveInkFrame frame);

class DecodedLiveInkChunk {
  const DecodedLiveInkChunk({
    required this.senderSocketId,
    required this.chunk,
  });

  final String senderSocketId;
  final LiveInkChunk chunk;
}

class LiveInkReceiveScheduler {
  LiveInkReceiveScheduler({
    required LiveInkFrameDecoder decode,
    this.maxPendingSenders = 8,
    this.schedulingBudget = const Duration(milliseconds: 2),
  }) : _decode = decode;

  final LiveInkFrameDecoder _decode;
  final int maxPendingSenders;
  final Duration schedulingBudget;
  final LinkedHashMap<String, ReceivedLiveInkFrame> _pending = LinkedHashMap();
  final StreamController<DecodedLiveInkChunk> _chunks =
      StreamController<DecodedLiveInkChunk>.broadcast();
  final Stopwatch _schedulingSlice = Stopwatch();

  bool _inFlight = false;
  bool _closed = false;
  int _generation = 0;
  Timer? _yieldTimer;
  int senderLimitDrops = 0;
  int decodeAttempts = 0;
  int decodeSuccesses = 0;
  int decodeErrors = 0;

  Stream<DecodedLiveInkChunk> get chunks => _chunks.stream;
  bool get inFlight => _inFlight;
  int get pendingSenderCount => _pending.length;

  void add(ReceivedLiveInkFrame frame) {
    if (_closed) return;
    final sender = frame.senderSocketId;
    if (_pending.containsKey(sender)) {
      _pending[sender] = frame;
    } else {
      if (_pending.length >= maxPendingSenders) {
        senderLimitDrops++;
        return;
      }
      _pending[sender] = frame;
    }
    _drain();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _yieldTimer?.cancel();
    _pending.clear();
    await _chunks.close();
  }

  void _drain() {
    if (_closed || _inFlight || _yieldTimer != null || _pending.isEmpty) {
      return;
    }
    if (!_schedulingSlice.isRunning) _schedulingSlice.start();

    final sender = _pending.keys.first;
    final frame = _pending.remove(sender)!;
    _inFlight = true;
    final generation = _generation;
    Future<void>.microtask(() async {
          decodeAttempts++;
          final chunk = await _decode(frame);
          if (!_closed && generation == _generation) {
            decodeSuccesses++;
            _chunks.add(
              DecodedLiveInkChunk(senderSocketId: sender, chunk: chunk),
            );
          }
        })
        .catchError((Object _) {
          if (!_closed && generation == _generation) decodeErrors++;
        })
        .whenComplete(() {
          if (_closed || generation != _generation) return;
          _inFlight = false;
          final sameSenderLatest = _pending.remove(sender);
          if (sameSenderLatest != null) {
            _pending[sender] = sameSenderLatest;
          }
          if (_schedulingSlice.elapsed >= schedulingBudget) {
            _schedulingSlice
              ..stop()
              ..reset();
            _yieldTimer = Timer(Duration.zero, () {
              _yieldTimer = null;
              _drain();
            });
          } else {
            _drain();
          }
        });
  }
}
