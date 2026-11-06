import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Local-only anchor for content sent to the assistant.
@immutable
sealed class AiSourceLocation {
  const AiSourceLocation();
}

final class AiElementSource extends AiSourceLocation {
  AiElementSource(Iterable<String> ids) : ids = Set.unmodifiable(ids);

  final Set<String> ids;
}

final class AiPageSource extends AiSourceLocation {
  const AiPageSource(this.pageId);

  final String pageId;
}

final class AiRegionSource extends AiSourceLocation {
  const AiRegionSource(this.bounds, {this.pageId});

  /// Page-relative when [pageId] is set, otherwise in infinite-canvas space.
  final Rect bounds;
  final String? pageId;
}
