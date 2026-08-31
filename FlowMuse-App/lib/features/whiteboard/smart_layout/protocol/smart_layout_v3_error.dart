/// v3 协议错误码（冻结于 docs/研发记录/specs/smart-layout-v3/protocol/protocol.md；
/// Dart/Go 双端同名 snake_case 映射，fixtures 双端同类拒绝）。
enum SmartLayoutV3ErrorCode {
  invalidRequest('invalid_request'),
  unknownField('unknown_field'),
  unknownEnum('unknown_enum'),
  danglingReference('dangling_reference'),
  duplicateReference('duplicate_reference'),
  referenceCycle('reference_cycle'),
  limitExceeded('limit_exceeded');

  const SmartLayoutV3ErrorCode(this.wireName);

  final String wireName;

  static SmartLayoutV3ErrorCode fromWireName(String name) =>
      SmartLayoutV3ErrorCode.values.firstWhere(
        (code) => code.wireName == name,
        orElse: () => throw ArgumentError('未知错误码: $name'),
      );
}

/// 错误 envelope：{"code", "message", "field"?}。
class SmartLayoutV3Error {
  const SmartLayoutV3Error({
    required this.code,
    required this.message,
    this.field,
  });

  factory SmartLayoutV3Error.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference({'code', 'message', 'field'}).isNotEmpty) {
      throw const SmartLayoutV3ProtocolException(
        SmartLayoutV3Error(
          code: SmartLayoutV3ErrorCode.unknownField,
          message: '错误 envelope 含未知字段',
        ),
      );
    }
    final codeRaw = json['code'];
    final message = json['message'];
    if (codeRaw is! String || message is! String) {
      throw const SmartLayoutV3ProtocolException(
        SmartLayoutV3Error(
          code: SmartLayoutV3ErrorCode.invalidRequest,
          message: '错误 envelope 字段类型错误',
        ),
      );
    }
    final field = json['field'];
    if (field != null && field is! String) {
      throw const SmartLayoutV3ProtocolException(
        SmartLayoutV3Error(
          code: SmartLayoutV3ErrorCode.invalidRequest,
          message: 'error.field 必须是字符串',
        ),
      );
    }
    return SmartLayoutV3Error(
      code: SmartLayoutV3ErrorCode.fromWireName(codeRaw),
      message: message,
      field: field as String?,
    );
  }

  final SmartLayoutV3ErrorCode code;
  final String message;
  final String? field;

  Map<String, Object?> toJson() => {
    'code': code.wireName,
    'message': message,
    if (field != null) 'field': field,
  };

  @override
  bool operator ==(Object other) =>
      other is SmartLayoutV3Error &&
      other.code == code &&
      other.message == message &&
      other.field == field;

  @override
  int get hashCode => Object.hash(code, message, field);

  @override
  String toString() =>
      'SmartLayoutV3Error(${code.wireName}, $message'
      '${field == null ? '' : ', field: $field'})';
}

/// 协议解析/校验失败异常：携带结构化 [SmartLayoutV3Error]。
class SmartLayoutV3ProtocolException implements Exception {
  const SmartLayoutV3ProtocolException(this.error);

  final SmartLayoutV3Error error;

  @override
  String toString() => 'SmartLayoutV3ProtocolException($error)';
}
