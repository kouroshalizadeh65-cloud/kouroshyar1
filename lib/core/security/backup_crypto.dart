import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String kouroshyarEncryptedBackupFormat = 'kouroshyar-encrypted-backup-v2';
const int kouroshyarBackupKdfIterations = 210000;
const String _magicText = 'KOUROSHYAR-ENCRYPTED-BACKUP-V2\n';

class BackupDecryptionException implements Exception {
  const BackupDecryptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupEncryptionHeader {
  const BackupEncryptionHeader({
    required this.format,
    required this.createdAt,
    required this.iterations,
    required this.cipher,
    required this.kdf,
  });

  final String format;
  final DateTime? createdAt;
  final int iterations;
  final String cipher;
  final String kdf;
}

class BackupCrypto {
  BackupCrypto._();

  static final List<int> _magic = utf8.encode(_magicText);
  static final AesGcm _cipher = AesGcm.with256bits();

  static bool isEncryptedBytes(List<int> bytes) {
    if (bytes.length < _magic.length + 4) return false;
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) return false;
    }
    return true;
  }

  static BackupEncryptionHeader? readHeader(List<int> bytes) {
    if (!isEncryptedBytes(bytes)) return null;
    final parsed = _parseEnvelope(bytes);
    final header = parsed.header;
    return BackupEncryptionHeader(
      format: header['format']?.toString() ?? '',
      createdAt: DateTime.tryParse(header['createdAt']?.toString() ?? ''),
      iterations: (header['iterations'] as num?)?.toInt() ?? 0,
      cipher: header['cipher']?.toString() ?? '',
      kdf: header['kdf']?.toString() ?? '',
    );
  }

  static Future<Uint8List> encryptBytes(
    List<int> clearBytes, {
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.length < 4) {
      throw ArgumentError('رمز پشتیبان باید حداقل ۴ نویسه باشد.');
    }

    final salt = _randomBytes(16);
    final header = <String, dynamic>{
      'format': kouroshyarEncryptedBackupFormat,
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': kouroshyarBackupKdfIterations,
      'salt': base64UrlEncode(salt),
      'cipher': 'AES-256-GCM',
    };
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
    final key = await _deriveKey(
      password: normalizedPassword,
      salt: salt,
      iterations: kouroshyarBackupKdfIterations,
    );
    final secretBox = await _cipher.encrypt(
      clearBytes,
      secretKey: key,
      aad: headerBytes,
    );
    final encryptedPayload = secretBox.concatenation();
    final headerLength = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);

    return Uint8List.fromList(<int>[
      ..._magic,
      ...headerLength.buffer.asUint8List(),
      ...headerBytes,
      ...encryptedPayload,
    ]);
  }

  static Future<Uint8List> decryptBytes(
    List<int> encryptedBytes, {
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      throw const BackupDecryptionException('رمز فایل پشتیبان وارد نشده است.');
    }

    try {
      final parsed = _parseEnvelope(encryptedBytes);
      final header = parsed.header;
      if (header['format'] != kouroshyarEncryptedBackupFormat || header['version'] != 2) {
        throw const BackupDecryptionException('قالب فایل پشتیبان رمزگذاری‌شده پشتیبانی نمی‌شود.');
      }
      final iterations = (header['iterations'] as num?)?.toInt() ?? 0;
      if (iterations < 10000 || iterations > 2000000) {
        throw const BackupDecryptionException('پارامتر امنیتی فایل پشتیبان معتبر نیست.');
      }
      final saltText = header['salt']?.toString() ?? '';
      final salt = base64Url.decode(saltText);
      if (salt.length < 16) {
        throw const BackupDecryptionException('نمک امنیتی فایل پشتیبان معتبر نیست.');
      }
      final key = await _deriveKey(
        password: normalizedPassword,
        salt: salt,
        iterations: iterations,
      );
      final secretBox = SecretBox.fromConcatenation(
        parsed.payload,
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
        copy: false,
      );
      final clearBytes = await _cipher.decrypt(
        secretBox,
        secretKey: key,
        aad: parsed.headerBytes,
      );
      return Uint8List.fromList(clearBytes);
    } on BackupDecryptionException {
      rethrow;
    } catch (_) {
      throw const BackupDecryptionException('رمز پشتیبان نادرست است یا فایل دست‌کاری/خراب شده است.');
    }
  }

  static Future<SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    required int iterations,
  }) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  static ({Map<String, dynamic> header, Uint8List headerBytes, Uint8List payload}) _parseEnvelope(List<int> bytes) {
    if (!isEncryptedBytes(bytes)) {
      throw const BackupDecryptionException('فایل انتخاب‌شده پشتیبان رمزگذاری‌شده کوروش‌یار نیست.');
    }
    final lengthOffset = _magic.length;
    final lengthBytes = Uint8List.fromList(bytes.sublist(lengthOffset, lengthOffset + 4));
    final headerLength = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
    final headerStart = lengthOffset + 4;
    final headerEnd = headerStart + headerLength;
    if (headerLength <= 0 || headerEnd >= bytes.length) {
      throw const BackupDecryptionException('ساختار فایل پشتیبان رمزگذاری‌شده ناقص است.');
    }
    final headerBytes = Uint8List.fromList(bytes.sublist(headerStart, headerEnd));
    final decoded = jsonDecode(utf8.decode(headerBytes));
    if (decoded is! Map) {
      throw const BackupDecryptionException('سرآیند فایل پشتیبان معتبر نیست.');
    }
    final payload = Uint8List.fromList(bytes.sublist(headerEnd));
    if (payload.length <= _cipher.nonceLength + _cipher.macAlgorithm.macLength) {
      throw const BackupDecryptionException('محتوای رمزگذاری‌شده فایل پشتیبان ناقص است.');
    }
    return (
      header: Map<String, dynamic>.from(decoded),
      headerBytes: headerBytes,
      payload: payload,
    );
  }
}
