const String base62Digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String generateKeyBetween(
  String? a,
  String? b, {
  String digits = base62Digits,
}) {
  if (a != null) {
    validateOrderKey(a, digits: digits);
  }
  if (b != null) {
    validateOrderKey(b, digits: digits);
  }
  if (a != null && b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }
  if (a == null) {
    if (b == null) {
      return 'a${digits[0]}';
    }

    final ib = _getIntegerPart(b);
    final fb = b.substring(ib.length);
    if (ib == 'A${List.filled(26, digits[0]).join()}') {
      return ib + _midpoint('', fb, digits);
    }
    if (ib.compareTo(b) < 0) {
      return ib;
    }
    final result = _decrementInteger(ib, digits);
    if (result == null) {
      throw ArgumentError('cannot decrement any more');
    }
    return result;
  }

  if (b == null) {
    final ia = _getIntegerPart(a);
    final fa = a.substring(ia.length);
    final i = _incrementInteger(ia, digits);
    return i ?? ia + _midpoint(fa, null, digits);
  }

  final ia = _getIntegerPart(a);
  final fa = a.substring(ia.length);
  final ib = _getIntegerPart(b);
  final fb = b.substring(ib.length);
  if (ia == ib) {
    return ia + _midpoint(fa, fb, digits);
  }
  final i = _incrementInteger(ia, digits);
  if (i == null) {
    throw ArgumentError('cannot increment any more');
  }
  if (i.compareTo(b) < 0) {
    return i;
  }
  return ia + _midpoint(fa, null, digits);
}

List<String> generateNKeysBetween(
  String? a,
  String? b,
  int n, {
  String digits = base62Digits,
}) {
  if (n < 0) {
    throw ArgumentError('n must be non-negative');
  }
  if (n == 0) {
    return const [];
  }
  if (n == 1) {
    return [generateKeyBetween(a, b, digits: digits)];
  }
  if (b == null) {
    var c = generateKeyBetween(a, b, digits: digits);
    final result = [c];
    for (var i = 0; i < n - 1; i += 1) {
      c = generateKeyBetween(c, b, digits: digits);
      result.add(c);
    }
    return result;
  }
  if (a == null) {
    var c = generateKeyBetween(a, b, digits: digits);
    final result = [c];
    for (var i = 0; i < n - 1; i += 1) {
      c = generateKeyBetween(a, c, digits: digits);
      result.add(c);
    }
    return result.reversed.toList();
  }
  final mid = n ~/ 2;
  final c = generateKeyBetween(a, b, digits: digits);
  return [
    ...generateNKeysBetween(a, c, mid, digits: digits),
    c,
    ...generateNKeysBetween(c, b, n - mid - 1, digits: digits),
  ];
}

void validateOrderKey(String key, {String digits = base62Digits}) {
  final validChars = key.split('').every(digits.contains);
  if (key == 'A${List.filled(26, digits[0]).join()}' || !validChars) {
    throw ArgumentError('invalid order key: $key');
  }
  final integerPart = _getIntegerPart(key);
  final fractionalPart = key.substring(integerPart.length);
  if (fractionalPart.endsWith(digits[0])) {
    throw ArgumentError('invalid order key: $key');
  }
}

String _midpoint(String a, String? b, String digits) {
  final zero = digits[0];
  if (b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }
  if (a.endsWith(zero) || (b != null && b.endsWith(zero))) {
    throw ArgumentError('trailing zero');
  }
  if (b != null && b.isNotEmpty) {
    var n = 0;
    while ((n < a.length ? a[n] : zero) == b[n]) {
      n += 1;
    }
    if (n > 0) {
      return b.substring(0, n) +
          _midpoint(a.substring(n), b.substring(n), digits);
    }
  }

  final digitA = a.isNotEmpty ? digits.indexOf(a[0]) : 0;
  final digitB = b != null ? digits.indexOf(b[0]) : digits.length;
  if (digitA < 0 || digitB < 0) {
    throw ArgumentError('invalid digit');
  }
  if (digitB - digitA > 1) {
    final midDigit = ((digitA + digitB) * 0.5).round();
    return digits[midDigit];
  }
  if (b != null && b.length > 1) {
    return b.substring(0, 1);
  }
  return digits[digitA] + _midpoint(a.substring(1), null, digits);
}

void _validateInteger(String integerPart) {
  if (integerPart.length != _getIntegerLength(integerPart[0])) {
    throw ArgumentError('invalid integer part of order key: $integerPart');
  }
}

int _getIntegerLength(String head) {
  final code = head.codeUnitAt(0);
  if (code >= 'a'.codeUnitAt(0) && code <= 'z'.codeUnitAt(0)) {
    return code - 'a'.codeUnitAt(0) + 2;
  }
  if (code >= 'A'.codeUnitAt(0) && code <= 'Z'.codeUnitAt(0)) {
    return 'Z'.codeUnitAt(0) - code + 2;
  }
  throw ArgumentError('invalid order key head: $head');
}

String _getIntegerPart(String key) {
  final integerPartLength = _getIntegerLength(key[0]);
  if (integerPartLength > key.length) {
    throw ArgumentError('invalid order key: $key');
  }
  return key.substring(0, integerPartLength);
}

String? _incrementInteger(String x, String digits) {
  _validateInteger(x);
  final head = x[0];
  final tail = x.substring(1).split('');
  var carry = true;
  for (var i = tail.length - 1; carry && i >= 0; i -= 1) {
    final d = digits.indexOf(tail[i]) + 1;
    if (d == digits.length) {
      tail[i] = digits[0];
    } else {
      tail[i] = digits[d];
      carry = false;
    }
  }
  if (carry) {
    if (head == 'Z') {
      return 'a${digits[0]}';
    }
    if (head == 'z') {
      return null;
    }
    final h = String.fromCharCode(head.codeUnitAt(0) + 1);
    if (h.compareTo('a') > 0) {
      tail.add(digits[0]);
    } else {
      tail.removeLast();
    }
    return h + tail.join();
  }
  return head + tail.join();
}

String? _decrementInteger(String x, String digits) {
  _validateInteger(x);
  final head = x[0];
  final tail = x.substring(1).split('');
  var borrow = true;
  for (var i = tail.length - 1; borrow && i >= 0; i -= 1) {
    final d = digits.indexOf(tail[i]) - 1;
    if (d == -1) {
      tail[i] = digits.substring(digits.length - 1);
    } else {
      tail[i] = digits[d];
      borrow = false;
    }
  }
  if (borrow) {
    if (head == 'a') {
      return 'Z${digits.substring(digits.length - 1)}';
    }
    if (head == 'A') {
      return null;
    }
    final h = String.fromCharCode(head.codeUnitAt(0) - 1);
    if (h.compareTo('Z') < 0) {
      tail.add(digits.substring(digits.length - 1));
    } else {
      tail.removeLast();
    }
    return h + tail.join();
  }
  return head + tail.join();
}
