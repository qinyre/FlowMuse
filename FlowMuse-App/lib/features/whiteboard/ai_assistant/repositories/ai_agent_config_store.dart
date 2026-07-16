import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiAgentConfig {
  const AiAgentConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Uri get chatCompletionsUri {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('请输入有效的 HTTP(S) API 地址');
    }
    final basePath = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final path = basePath.endsWith('/chat/completions')
        ? basePath
        : '$basePath/chat/completions';
    return uri.replace(path: path);
  }

  void validate() {
    chatCompletionsUri;
    if (apiKey.trim().isEmpty) throw const FormatException('请输入 API Key');
    if (model.trim().isEmpty) throw const FormatException('请输入模型名称');
  }

  Map<String, String> toJson() => {
    'baseUrl': baseUrl.trim(),
    'apiKey': apiKey.trim(),
    'model': model.trim(),
  };

  factory AiAgentConfig.fromJson(Map<String, Object?> json) {
    final config = AiAgentConfig(
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
    config.validate();
    return config;
  }
}

class AiAgentConfigStore {
  AiAgentConfigStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'flowmuse.ai.agent.config';
  final FlutterSecureStorage _storage;

  Future<AiAgentConfig?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null || value.isEmpty) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('AI 配置格式无效');
    return AiAgentConfig.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> write(AiAgentConfig config) {
    config.validate();
    return _storage.write(key: _key, value: jsonEncode(config.toJson()));
  }
}

final defaultAiAgentConfigStore = AiAgentConfigStore();
