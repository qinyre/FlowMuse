/// Canvas-level settings from the .markdraw frontmatter.
class CanvasSettings {
  final int formatVersion;
  final String background;
  final int? grid;
  final String? name;

  const CanvasSettings({
    this.formatVersion = 1,
    this.background = '#ffffff',
    this.grid,
    this.name,
  });

  bool get isDefault =>
      formatVersion == 1 &&
      background == '#ffffff' &&
      grid == null &&
      name == null;

  CanvasSettings copyWith({
    int? formatVersion,
    String? background,
    int? grid,
    bool clearGrid = false,
    String? name,
    bool clearName = false,
  }) {
    return CanvasSettings(
      formatVersion: formatVersion ?? this.formatVersion,
      background: background ?? this.background,
      grid: clearGrid ? null : (grid ?? this.grid),
      name: clearName ? null : (name ?? this.name),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasSettings &&
          formatVersion == other.formatVersion &&
          background == other.background &&
          grid == other.grid &&
          name == other.name;

  @override
  int get hashCode => Object.hash(formatVersion, background, grid, name);

  @override
  String toString() =>
      'CanvasSettings(v$formatVersion, bg=$background, grid=$grid, name=$name)';
}
