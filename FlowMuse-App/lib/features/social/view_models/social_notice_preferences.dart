import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';

@immutable
class SocialNoticePreferences {
  const SocialNoticePreferences({
    this.enabled = true,
    this.preview = true,
    this.doNotDisturb = false,
  });

  final bool enabled, preview, doNotDisturb;
}

final socialNoticeSettingsRepositoryProvider = Provider(
  (ref) => defaultLocalSettingsRepository,
);
final socialNoticePreferencesProvider =
    AsyncNotifierProvider<
      SocialNoticePreferencesViewModel,
      SocialNoticePreferences
    >(SocialNoticePreferencesViewModel.new);

class SocialNoticePreferencesViewModel
    extends AsyncNotifier<SocialNoticePreferences> {
  static const storageKey = 'social.notice.preferences.v1';

  @override
  Future<SocialNoticePreferences> build() async {
    try {
      final raw = await ref
          .watch(socialNoticeSettingsRepositoryProvider)
          .readString(storageKey);
      if (raw == null) return const SocialNoticePreferences();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SocialNoticePreferences(
        enabled: json['enabled'] != false,
        preview: json['preview'] != false,
        doNotDisturb: json['doNotDisturb'] == true,
      );
    } catch (_) {
      debugPrint(
        '[FlowMuseSocial] notice settings unavailable; reminders paused',
      );
      return const SocialNoticePreferences(enabled: false, preview: false);
    }
  }

  Future<void> save(SocialNoticePreferences value) async {
    await ref
        .read(socialNoticeSettingsRepositoryProvider)
        .writeString(
          storageKey,
          jsonEncode({
            'enabled': value.enabled,
            'preview': value.preview,
            'doNotDisturb': value.doNotDisturb,
          }),
        );
    if (ref.mounted) state = AsyncData(value);
  }
}
