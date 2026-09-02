import 'smart_layout_v3_error.dart';

/// 严格 JSON 读取器：未知字段 unknown_field、类型错误 invalid_request、
/// 嵌套路径记入 error.field。协议无动态 map 透传。
class SmartLayoutV3JsonReader {
  const SmartLayoutV3JsonReader();

  static final RegExp fingerprintPattern = RegExp(r'^[0-9a-f]{16}$');

  /// 字段路径拼接：根层无前导点（'assets' 而非 '.assets'）。
  static String fieldOf(String prefix, String key) =>
      prefix.isEmpty ? key : '$prefix.$key';

  static const requestRootKeys = <String>{
    'protocolVersion',
    'pageId',
    'sceneRevision',
    'assets',
    'marks',
    'exactTexts',
    'sourceRefs',
  };

  static const responseRootKeys = <String>{
    'protocolVersion',
    'requestId',
    'regions',
    'warnings',
  };

  Map<String, Object?> rootObject(Object? value, Set<String> knownKeys) =>
      object(value, '', knownKeys);

  Never invalid(String field, String message) =>
      throw SmartLayoutV3ProtocolException(
        SmartLayoutV3Error(
          code: SmartLayoutV3ErrorCode.invalidRequest,
          message: message,
          field: field.isEmpty ? null : field,
        ),
      );

  Never unknownField(String field) => throw SmartLayoutV3ProtocolException(
    SmartLayoutV3Error(
      code: SmartLayoutV3ErrorCode.unknownField,
      message: '未知字段',
      field: field,
    ),
  );

  Never reject(SmartLayoutV3ErrorCode code, String field, String message) =>
      throw SmartLayoutV3ProtocolException(
        SmartLayoutV3Error(code: code, message: message, field: field),
      );

  Map<String, Object?> object(
    Object? value,
    String field,
    Set<String> knownKeys,
  ) {
    if (value is! Map) {
      invalid(field, '$field 必须是对象');
    }
    for (final key in value.keys) {
      if (key is! String) {
        invalid(field, '$field 的键必须是字符串');
      }
      if (!knownKeys.contains(key)) {
        unknownField(field.isEmpty ? key : '$field.$key');
      }
    }
    return Map<String, Object?>.from(value);
  }

  void require(Map<String, Object?> object, String key, String fieldPrefix) {
    if (!object.containsKey(key)) {
      invalid(fieldPrefix.isEmpty ? key : '$fieldPrefix.$key', '缺少必填字段 $key');
    }
  }

  String string(Map<String, Object?> object, String key, String fieldPrefix) {
    final value = object[key];
    if (value is! String) {
      invalid(fieldOf(fieldPrefix, key), '$key 必须是字符串');
    }
    return value;
  }

  int nonNegativeInt(
    Map<String, Object?> object,
    String key,
    String fieldPrefix,
  ) {
    final value = object[key];
    if (value is int && value >= 0) return value;
    invalid(fieldOf(fieldPrefix, key), '$key 必须是非负整数');
  }

  double unitInterval(
    Map<String, Object?> object,
    String key,
    String fieldPrefix,
  ) {
    final value = object[key];
    if (value is num && value >= 0 && value <= 1) {
      return value.toDouble();
    }
    invalid(fieldOf(fieldPrefix, key), '$key 必须在 [0,1]');
  }

  List<Object?> list(
    Map<String, Object?> object,
    String key,
    String fieldPrefix,
  ) {
    final value = object[key];
    if (value is! List) {
      invalid(fieldOf(fieldPrefix, key), '$key 必须是数组');
    }
    return value;
  }

  Map<String, Object?> objectAt(
    List<Object?> list,
    int index,
    String fieldPrefix,
    Set<String> knownKeys,
  ) => object(list[index], '$fieldPrefix[$index]', knownKeys);

  void limit(int length, int max, String field, String what) {
    if (length > max) {
      reject(SmartLayoutV3ErrorCode.limitExceeded, field, '$what 超过上限 $max');
    }
  }

  void nonEmptyList(List<Object?> list, String field) {
    if (list.isEmpty) {
      invalid(field, '必须是非空数组');
    }
  }

  void nonEmpty(String value, String field) {
    if (value.isEmpty) {
      invalid(field, '必须非空');
    }
  }

  void unique(Iterable<String> values, String field, String what) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        reject(
          SmartLayoutV3ErrorCode.duplicateReference,
          field,
          '$what 重复: $value',
        );
      }
    }
  }

  T enumValue<T>(
    Object? value,
    String field,
    Map<String, T> table,
    String what,
  ) {
    if (value is! String) {
      invalid(field, '$what 必须是字符串');
    }
    final parsed = table[value];
    if (parsed == null) {
      reject(SmartLayoutV3ErrorCode.unknownEnum, field, '未知 $what 枚举: $value');
    }
    return parsed;
  }

  void fingerprint(String value, String field) {
    if (!fingerprintPattern.hasMatch(value)) {
      invalid(field, '必须是 16 位小写 hex');
    }
  }
}
