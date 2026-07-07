import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A unique identifier for a drawing element.
class ElementId {
  final String value;

  const ElementId(this.value);

  /// Generates a new unique element ID.
  factory ElementId.generate() => ElementId(_uuid.v4());

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ElementId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
