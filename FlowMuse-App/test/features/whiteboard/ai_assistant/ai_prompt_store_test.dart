import 'package:flow_muse/features/whiteboard/ai_assistant/repositories/ai_prompt_store.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自定义指令去重、限制十条并支持删除', () async {
    final settings = _MemorySettings();
    final store = AiPromptStore(settings);

    for (var index = 0; index < 12; index++) {
      await store.save('指令 $index');
    }
    await store.save('指令 5');

    final prompts = await store.load();
    expect(prompts, hasLength(AiPromptStore.maxPrompts));
    expect(prompts.first, '指令 5');
    expect(prompts.where((prompt) => prompt == '指令 5'), hasLength(1));
    expect(await store.remove('指令 5'), isNot(contains('指令 5')));
  });

  test('损坏的自定义指令数据安全降级为空列表', () async {
    final settings = _MemorySettings()..value = '{broken';

    expect(await AiPromptStore(settings).load(), isEmpty);
  });
}

class _MemorySettings extends LocalSettingsRepository {
  _MemorySettings() : super(() async => throw UnsupportedError('unused'));

  String? value;

  @override
  Future<String?> readString(String key) async => value;

  @override
  Future<void> writeString(String key, String value) async {
    this.value = value;
  }
}
