import 'dart:convert';

import '../../../../shared/storage/local_settings_repository.dart';

class AiPromptStore {
  AiPromptStore(this._settings);

  static const _key = 'flowmuse.ai.custom_prompts.v1';
  static const maxPrompts = 10;
  final LocalSettingsRepository _settings;

  Future<List<String>> load() async {
    final raw = await _settings.readString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final value in decoded)
          if (value is String && value.trim().isNotEmpty) value.trim(),
      ].take(maxPrompts).toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<List<String>> save(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty || normalized.runes.length > 1000) {
      throw const FormatException('AI 指令长度无效');
    }
    final prompts = [
      normalized,
      for (final item in await load())
        if (item != normalized) item,
    ].take(maxPrompts).toList(growable: false);
    await _settings.writeString(_key, jsonEncode(prompts));
    return prompts;
  }

  Future<List<String>> remove(String prompt) async {
    final prompts = [
      for (final item in await load())
        if (item != prompt) item,
    ];
    await _settings.writeString(_key, jsonEncode(prompts));
    return prompts;
  }
}

final defaultAiPromptStore = AiPromptStore(defaultLocalSettingsRepository);
