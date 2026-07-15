import '../core/elements/text_element.dart';

class MathTextUtils {
  const MathTextUtils._();

  static bool isMathText(TextElement element) {
    final flowMuse = element.customData?['flowMuse'];
    if (flowMuse is Map<String, Object?>) {
      return flowMuse['smartLayoutType'] == 'math';
    }
    if (flowMuse is Map) {
      return flowMuse['smartLayoutType'] == 'math';
    }
    return false;
  }
}
