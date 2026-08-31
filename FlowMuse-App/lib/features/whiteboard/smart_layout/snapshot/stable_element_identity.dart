import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

/// 智能排版 v3 引用的元素稳定标识：即元素 id 的规范字符串形态。
///
/// 远端 upsert 可能以不同列表顺序合入相同元素集合，一切按内容的
/// 比较/排序/指纹都必须以 [StableElementIdentity] 为键，而不是列表下标。
class StableElementIdentity implements Comparable<StableElementIdentity> {
  const StableElementIdentity(this.value);

  factory StableElementIdentity.of(Element element) =>
      StableElementIdentity(element.id.value);

  /// 规范字符串（ElementId 的 value）。
  final String value;

  @override
  int compareTo(StableElementIdentity other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is StableElementIdentity && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StableElementIdentity($value)';
}
