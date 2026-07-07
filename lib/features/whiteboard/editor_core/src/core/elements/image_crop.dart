/// Normalized crop rectangle for an image element.
///
/// All values are in the 0–1 range, where (0, 0) is top-left and
/// (1, 1) is bottom-right of the original image.
class ImageCrop {
  final double x;
  final double y;
  final double width;
  final double height;

  const ImageCrop({this.x = 0, this.y = 0, this.width = 1, this.height = 1});

  /// Whether this crop represents the full image (no cropping).
  bool get isFullImage => x == 0 && y == 0 && width == 1 && height == 1;

  ImageCrop copyWith({double? x, double? y, double? width, double? height}) {
    return ImageCrop(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageCrop &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'ImageCrop($x, $y, $width, $height)';
}
