String shareArtifactFileName(String title, String extension) {
  final base = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return '${base.isEmpty ? 'drawing' : base}.$extension';
}
