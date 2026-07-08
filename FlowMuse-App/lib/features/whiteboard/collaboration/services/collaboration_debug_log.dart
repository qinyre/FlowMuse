import 'package:flutter/foundation.dart';

class CollaborationDebugLog {
  const CollaborationDebugLog._();

  static void write(
    String area,
    String event, [
    Map<String, Object?> fields = const {},
  ]) {
    if (!kDebugMode) {
      return;
    }
    final details = fields.entries
        .map((entry) => '${entry.key}=${_format(entry.value)}')
        .join(' ');
    debugPrint(
      details.isEmpty
          ? '[FlowMuseCollab][$area][$event]'
          : '[FlowMuseCollab][$area][$event] $details',
    );
  }

  static String elementSummary(List<Map<String, Object?>> elements) {
    final summarized = elements
        .take(5)
        .map((element) {
          final id = (element['id'] as String?) ?? '';
          final shortId = id.length > 8 ? id.substring(0, 8) : id;
          final version = element['version'];
          final nonce = element['versionNonce'];
          final deleted = element['isDeleted'];
          return '{id=$shortId,v=$version,n=$nonce,del=$deleted}';
        })
        .join(',');
    return elements.length > 5 ? '[$summarized,...]' : '[$summarized]';
  }

  static int sceneVersion(List<Map<String, Object?>> elements) {
    return elements.fold(0, (sum, element) {
      final version = element['version'];
      return sum + (version is num ? version.toInt() : 0);
    });
  }

  static String _format(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is String) {
      return value;
    }
    if (value is Iterable) {
      return '[${value.map(_format).join(',')}]';
    }
    if (value is Map) {
      return '{${value.entries.map((entry) => '${entry.key}:${_format(entry.value)}').join(',')}}';
    }
    return value.toString();
  }
}
