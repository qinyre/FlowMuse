import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';
import '../../library/repositories/library_repository.dart';

final guideSettingsRepositoryProvider = Provider(
  (ref) => defaultLocalSettingsRepository,
);
final guideWelcomeProvider = AsyncNotifierProvider<GuideWelcomeViewModel, bool>(
  GuideWelcomeViewModel.new,
);

class GuideWelcomeViewModel extends AsyncNotifier<bool> {
  static const storageKey = 'guide.welcome.completed.v1';

  @override
  Future<bool> build() async {
    try {
      final settings = ref.watch(guideSettingsRepositoryProvider);
      if (await settings.readBool(storageKey) == true) return false;
      final index = await ref.watch(libraryIndexProvider.future);
      if (index.notes.isNotEmpty ||
          index.notebooks.isNotEmpty ||
          index.tags.isNotEmpty) {
        await settings.writeBool(storageKey, true);
        return false;
      }
      return true;
    } catch (_) {
      debugPrint(
        '[FlowMuseGuide] welcome state unavailable; automatic introduction skipped',
      );
      return false;
    }
  }

  Future<void> dismiss() async {
    state = const AsyncData(false);
    try {
      await ref
          .read(guideSettingsRepositoryProvider)
          .writeBool(storageKey, true);
    } catch (_) {
      // A failed non-critical preference must never prevent starting a note.
      debugPrint('[FlowMuseGuide] welcome preference not saved');
    }
  }
}
