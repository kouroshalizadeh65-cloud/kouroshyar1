import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int _pinIterations = 60000;
const int _derivedKeyLength = 32;

String hashPinSecure(String pin) {
  final random = Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
  final derived = _pbkdf2(utf8.encode(pin), salt, _pinIterations, _derivedKeyLength);
  return 'pbkdf2-sha256:$_pinIterations:${base64UrlEncode(salt)}:${base64UrlEncode(derived)}';
}

bool verifyPinSecure(String typed, String stored) {
  final value = stored.trim();
  if (value.isEmpty) return false;
  if (value.startsWith('pbkdf2-sha256:')) {
    final parts = value.split(':');
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 10000 || iterations > 1000000) return false;
    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = _pbkdf2(utf8.encode(typed), salt, iterations, expected.length);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }
  if (value.startsWith('sha256:')) {
    final legacy = 'sha256:${sha256.convert(utf8.encode(typed))}';
    return _constantTimeEquals(utf8.encode(legacy), utf8.encode(value));
  }
  return _constantTimeEquals(utf8.encode(typed), utf8.encode(value));
}

bool pinHashNeedsUpgrade(String stored) => !stored.startsWith('pbkdf2-sha256:');

Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
  final hmac = Hmac(sha256, password);
  final result = BytesBuilder(copy: false);
  var blockIndex = 1;
  while (result.length < keyLength) {
    final block = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..setRange(salt.length, salt.length + 4, [
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ]);
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    result.add(t);
    blockIndex++;
  }
  return Uint8List.fromList(result.takeBytes().take(keyLength).toList());
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
