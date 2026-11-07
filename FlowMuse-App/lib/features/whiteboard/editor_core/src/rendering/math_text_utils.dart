import '../core/elements/latex_source.dart';
import '../core/elements/text_element.dart';

class MathTextUtils {
  const MathTextUtils._();

  static bool isMathText(TextElement element) => latex(element) != null;

  static String? explicitLatex(TextElement element) =>
      element.containerId == null ? standaloneLatex(element.text) : null;

  static String? latex(TextElement element) {
    final explicit = explicitLatex(element);
    if (explicit != null) return explicit;
    final flowMuse = element.customData?['flowMuse'];
    return flowMuse is Map && flowMuse['smartLayoutType'] == 'math'
        ? element.text
        : null;
  }
}
