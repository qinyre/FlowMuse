/// Utilities for generating sortable fractional-index strings.
///
/// Keys are base-62 strings (digits 0-9, uppercase A-Z, lowercase a-z) that
/// sort lexicographically. This allows inserting elements between any two
/// existing elements without renumbering.
class FractionalIndex {
  FractionalIndex._();

  static const String _chars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// Default midpoint character used when generating initial keys.
  static const String _mid = 'V'; // roughly middle of base-62

  /// Generate a key that sorts after [after].
  ///
  /// If [after] is null, returns the midpoint key.
  static String generateAfter(String? after) {
    if (after == null || after.isEmpty) return _mid;
    // Append midpoint character
    return '$after$_mid';
  }

  /// Generate a key that sorts before [before].
  ///
  /// If [before] is null, returns the midpoint key.
  static String generateBefore(String? before) {
    if (before == null || before.isEmpty) return _mid;

    // Find rightmost character that isn't the smallest ('0').
    // Decrement it and return.
    final chars = before.split('');
    for (var i = chars.length - 1; i >= 0; i--) {
      final idx = _chars.indexOf(chars[i]);
      if (idx > 0) {
        chars[i] = _chars[idx ~/ 2]; // halfway between '0' and current
        return chars.sublist(0, i + 1).join();
      }
    }
    // All characters are '0'; prepend '0' and add midpoint
    return '${before}0$_mid';
  }

  /// Generate a key that sorts between [a] and [b].
  ///
  /// Requires `a < b` lexicographically.
  static String generateBetween(String a, String b) {
    assert(a.compareTo(b) < 0, 'a must be less than b');

    // Find first position where they differ
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      final ca = i < a.length ? _chars.indexOf(a[i]) : 0;
      final cb = i < b.length ? _chars.indexOf(b[i]) : _chars.length;
      if (ca == cb) continue;

      if (cb - ca > 1) {
        // There's room between these two characters
        final mid = (ca + cb) ~/ 2;
        return a.substring(0, i) + _chars[mid];
      }

      // Adjacent characters — go deeper using a's suffix
      return a.substring(0, i + 1) +
          generateBetween(
            i + 1 < a.length ? a.substring(i + 1) : '',
            i + 1 < b.length ? b.substring(i + 1) : _chars[_chars.length - 1],
          );
    }

    // a is a prefix of b — insert between a and b at position a.length
    return '$a$_mid';
  }

  /// Generate [n] keys that sort between [after] and [before].
  ///
  /// Useful for assigning indices to multiple elements at once.
  static List<String> generateNKeys(int n, {String? after, String? before}) {
    if (n == 0) return [];
    if (n == 1) {
      if (after != null && before != null) {
        return [generateBetween(after, before)];
      }
      if (after != null) return [generateAfter(after)];
      if (before != null) return [generateBefore(before)];
      return [_mid];
    }

    final keys = <String>[];
    var current = after;
    for (var i = 0; i < n; i++) {
      final key = current != null && before != null
          ? generateBetween(current, before)
          : current != null
          ? generateAfter(current)
          : before != null
          ? generateBefore(before)
          : _mid;
      keys.add(key);
      current = key;
    }
    return keys;
  }
}
