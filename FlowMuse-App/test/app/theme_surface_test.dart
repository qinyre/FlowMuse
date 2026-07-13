import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('featured theme exposes its secondary and tertiary colors to Material', () {
    final preset = appThemePresetById(AppThemeId.starryBlue);
    final theme = AppTheme.fromPreset(preset);

    expect(theme.colorScheme.secondary, preset.secondaryColor);
    expect(theme.colorScheme.tertiary, preset.tertiaryColor);
    expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
  });

  testWidgets('night Material surfaces resolve from the active color scheme', (
    tester,
  ) async {
    final theme = AppTheme.fromPreset(appThemePresetById(AppThemeId.night));

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              AlertDialog(title: const Text('Dialog')),
              const TextField(),
              const FilledButton(onPressed: null, child: Text('Action')),
              const SearchBar(),
            ],
          ),
        ),
      ),
    );

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final card = tester.widget<Material>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)),
    );
    final dialogTitle = tester.widget<DefaultTextStyle>(
      find
          .ancestor(of: find.text('Dialog'), matching: find.byType(DefaultTextStyle))
          .first,
    );

    expect(dialog.backgroundColor ?? card.color, theme.colorScheme.surface);
    expect(dialogTitle.style.color, theme.colorScheme.onSurface);
    expect(
      theme.inputDecorationTheme.fillColor,
      theme.colorScheme.surfaceContainerHighest,
    );
    expect(theme.filledButtonTheme.style?.foregroundColor?.resolve({}), theme.colorScheme.onPrimary);
    expect(
      theme.searchBarTheme.backgroundColor?.resolve({}),
      theme.colorScheme.surfaceContainerHighest,
    );
  });
}
