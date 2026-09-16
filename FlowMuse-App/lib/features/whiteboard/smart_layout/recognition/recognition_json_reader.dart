/// 独立识别链路（POST /api/ink/smart-layout/recognize/v3）的严格 JSON
/// 读取器与错误码表（spec §3.5）。与旧 SmartLayoutV3Error 表完全独立，
/// 互不复用枚举值。
///
/// 解析方向决定泛型失败（未知字段/类型错误/未知枚举）的归类：
/// 请求侧=invalidSchema（400，客户端发送前自检），响应侧=
/// invalidProviderResponse（502，上游非法输出）。解析失败类错误一律
/// retryable=false（spec §3.5：invalidProviderResponse 不重试）。
library;

/// spec §3.5 错误表。wire 名与 Go 端 `layoutrecognitionv3` 同名映射。
enum RecognitionExceptionCode {
  invalidSchema('invalidSchema', false),
  duplicateId('duplicateId', false),
  limitExceeded('limitExceeded', false),
  textTooLong('textTooLong', false),
  badGeometry('badGeometry', false),
  auth('auth', false),
  busy('busy', true),
  unconfigured('unconfigured', false),
  providerTimeout('providerTimeout', true),
  providerError('providerError', true),
  invalidProviderResponse('invalidProviderResponse', false),
  internal('internal', false);

  const RecognitionExceptionCode(this.wireName, this.defaultRetryable);

  final String wireName;
  final bool defaultRetryable;

  static RecognitionExceptionCode fromWireName(String name) =>
      RecognitionExceptionCode.values.firstWhere(
        (code) => code.wireName == name,
        orElse: () => throw ArgumentError('未知错误码: $name'),
      );
}

/// 服务端错误 envelope：`{"error":{"code","message","retryable"}}`。
class RecognitionWireError {
  const RecognitionWireError({
    required this.code,
    required this.message,
    required this.retryable,
  });

  factory RecognitionWireError.fromJson(Map<String, Object?> json) {
    const envelopeKeys = {'code', 'message', 'retryable'};
    if (json.keys.toSet().difference(envelopeKeys).isNotEmpty) {
      throw const RecognitionProtocolException(
        RecognitionWireError(
          code: RecognitionExceptionCode.invalidSchema,
          message: '错误 envelope 含未知字段',
          retryable: false,
        ),
      );
    }
    final codeRaw = json['code'];
    final message = json['message'];
    final retryable = json['retryable'];
    if (codeRaw is! String || message is! String || retryable is! bool) {
      throw const RecognitionProtocolException(
        RecognitionWireError(
          code: RecognitionExceptionCode.invalidSchema,
          message: '错误 envelope 字段类型错误',
          retryable: false,
        ),
      );
    }
    return RecognitionWireError(
      code: RecognitionExceptionCode.fromWireName(codeRaw),
      message: message,
      retryable: retryable,
    );
  }

  final RecognitionExceptionCode code;
  final String message;
  final bool retryable;

  Map<String, Object?> toJson() => {
    'code': code.wireName,
    'message': message,
    'retryable': retryable,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognitionWireError &&
      other.code == code &&
      other.message == message &&
      other.retryable == retryable;

  @override
  int get hashCode => Object.hash(code, message, retryable);

  @override
  String toString() =>
      'RecognitionWireError(${code.wireName}, $message, '
      'retryable: $retryable)';
}

/// 协议解析/校验失败异常：携带结构化 [RecognitionWireError]。
class RecognitionProtocolException implements Exception {
  const RecognitionProtocolException(this.error);

  final RecognitionWireError error;

  @override
  String toString() => 'RecognitionProtocolException($error)';
}

/// 解析方向：请求（自检，400 口径）或响应（上游输出，502 口径）。
enum RecognitionParseSide { request, response }

/// 严格 JSON 读取器：未知字段、类型错误、越界一律抛
/// [RecognitionProtocolException]，嵌套路径记入 message。协议无动态
/// map 透传。镜像 SmartLayoutV3JsonReader 惯例但错误码表独立。
class RecognitionJsonReader {
  const RecognitionJsonReader([this.side = RecognitionParseSide.request]);

  final RecognitionParseSide side;

  static String fieldOf(String prefix, String key) =>
      prefix.isEmpty ? key : '$prefix.$key';

  Never invalid(String field, String message) =>
      side == RecognitionParseSide.request
      ? _throw(RecognitionExceptionCode.invalidSchema, field, message)
      : _throw(
          RecognitionExceptionCode.invalidProviderResponse,
          field,
          message,
        );

  Never unknownField(String field) => side == RecognitionParseSide.request
      ? _throw(RecognitionExceptionCode.invalidSchema, field, '未知字段')
      : _throw(RecognitionExceptionCode.invalidProviderResponse, field, '未知字段');

  Never _throw(RecognitionExceptionCode code, String field, String message) {
    throw RecognitionProtocolException(
      RecognitionWireError(
        code: code,
        message: field.isEmpty ? message : '$message（字段: $field）',
        retryable: false,
      ),
    );
  }

  Never reject(RecognitionExceptionCode code, String field, String message) =>
      _throw(code, field, message);

  Map<String, Object?> rootObject(Object? value, Set<String> knownKeys) =>
      object(value, '', knownKeys);

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
      invalid(fieldOf(fieldPrefix, key), '缺少必填字段 $key');
    }
  }

  String string(Map<String, Object?> object, String key, String fieldPrefix) {
    final value = object[key];
    if (value is! String) {
      invalid(fieldOf(fieldPrefix, key), '$key 必须是字符串');
    }
    return value;
  }

  void nonEmpty(String value, String field) {
    if (value.isEmpty) {
      invalid(field, '必须非空');
    }
  }

  /// id 类长度上限：超限归 limitExceeded（对齐旧协议惯例）。
  void idLimit(String value, int max, String field, String what) {
    if (value.runes.length > max) {
      reject(RecognitionExceptionCode.limitExceeded, field, '$what 超过 $max 字符');
    }
  }

  /// 正文类长度上限（Unicode 字符数，与 Go utf8.RuneCountInString 对齐）：
  /// 超限归 textTooLong。
  void textLimit(String value, int max, String field, String what) {
    if (value.runes.length > max) {
      reject(RecognitionExceptionCode.textTooLong, field, '$what 超过 $max 字符');
    }
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

  /// 有限正数（imageScale、lineHintHeight 等）：非数/NaN/Inf/≤0 归
  /// badGeometry（请求侧）或 invalidProviderResponse（响应侧）。
  double positiveFiniteDouble(
    Map<String, Object?> object,
    String key,
    String fieldPrefix,
  ) {
    final value = object[key];
    if (value is! num || !value.isFinite || value <= 0) {
      reject(
        side == RecognitionParseSide.request
            ? RecognitionExceptionCode.badGeometry
            : RecognitionExceptionCode.invalidProviderResponse,
        fieldOf(fieldPrefix, key),
        '$key 必须是有限正数',
      );
    }
    return value.toDouble();
  }

  /// [0,1] 闭区间有限数（confidence）。
  double unitInterval(
    Map<String, Object?> object,
    String key,
    String fieldPrefix,
  ) {
    final value = object[key];
    if (value is num && value.isFinite && value >= 0 && value <= 1) {
      return value.toDouble();
    }
    reject(
      side == RecognitionParseSide.request
          ? RecognitionExceptionCode.invalidSchema
          : RecognitionExceptionCode.invalidProviderResponse,
      fieldOf(fieldPrefix, key),
      '$key 必须在 [0,1]',
    );
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
      reject(RecognitionExceptionCode.limitExceeded, field, '$what 超过上限 $max');
    }
  }

  void nonEmptyList(List<Object?> list, String field) {
    if (list.isEmpty) {
      invalid(field, '必须是非空数组');
    }
  }

  /// 数组内 id 去重：请求侧=duplicateId（400），响应侧=
  /// invalidProviderResponse（502）。
  void unique(Iterable<String> values, String field, String what) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        reject(
          side == RecognitionParseSide.request
              ? RecognitionExceptionCode.duplicateId
              : RecognitionExceptionCode.invalidProviderResponse,
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
      reject(
        side == RecognitionParseSide.request
            ? RecognitionExceptionCode.invalidSchema
            : RecognitionExceptionCode.invalidProviderResponse,
        field,
        '未知 $what 枚举: $value',
      );
    }
    return parsed;
  }
}
