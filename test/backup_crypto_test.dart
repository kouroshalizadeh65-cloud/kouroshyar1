import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/core/security/backup_crypto.dart';

void main() {
  test('پشتیبان با رمز متفاوت از متن اصلی و قابل بازیابی است', () async {
    final clearBytes = utf8.encode('اطلاعات محرمانه پرونده و مدارک');
    final encrypted = await BackupCrypto.encryptBytes(
      clearBytes,
      password: 'secure-backup-123',
    );

    expect(BackupCrypto.isEncryptedBytes(encrypted), isTrue);
    expect(encrypted, isNot(equals(clearBytes)));

    final decrypted = await BackupCrypto.decryptBytes(
      encrypted,
      password: 'secure-backup-123',
    );
    expect(utf8.decode(decrypted), 'اطلاعات محرمانه پرونده و مدارک');
  });

  test('رمز اشتباه پشتیبان پذیرفته نمی‌شود', () async {
    final encrypted = await BackupCrypto.encryptBytes(
      utf8.encode('test'),
      password: 'correct-password',
    );

    await expectLater(
      BackupCrypto.decryptBytes(encrypted, password: 'wrong-password'),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('دست‌کاری محتوای پشتیبان با کنترل اصالت شناسایی می‌شود', () async {
    final encrypted = await BackupCrypto.encryptBytes(
      utf8.encode('sensitive-data'),
      password: 'tamper-password',
    );
    final tampered = List<int>.from(encrypted);
    tampered[tampered.length - 1] ^= 0x01;

    await expectLater(
      BackupCrypto.decryptBytes(tampered, password: 'tamper-password'),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('سرآیند پشتیبان رمزگذاری‌شده قابل شناسایی است', () async {
    final encrypted = await BackupCrypto.encryptBytes(
      utf8.encode('test'),
      password: 'header-password',
    );
    final header = BackupCrypto.readHeader(encrypted);

    expect(header, isNotNull);
    expect(header!.format, kouroshyarEncryptedBackupFormat);
    expect(header.cipher, 'AES-256-GCM');
    expect(header.iterations, kouroshyarBackupKdfIterations);
  });
}
