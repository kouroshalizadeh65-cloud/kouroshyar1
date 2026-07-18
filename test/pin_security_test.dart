import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/core/security/pin_security.dart';

void main() {
  test('رمز جدید با salt ذخیره و درست بررسی می‌شود', () {
    final first = hashPinSecure('123456');
    final second = hashPinSecure('123456');

    expect(first, startsWith('pbkdf2-sha256:'));
    expect(second, startsWith('pbkdf2-sha256:'));
    expect(first, isNot(second));
    expect(verifyPinSecure('123456', first), isTrue);
    expect(verifyPinSecure('654321', first), isFalse);
    expect(pinHashNeedsUpgrade(first), isFalse);
  });

  test('هش قدیمی نسخه 3.6.44 برای مهاجرت قابل بررسی است', () {
    const legacy = 'sha256:8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92';

    expect(verifyPinSecure('123456', legacy), isTrue);
    expect(verifyPinSecure('654321', legacy), isFalse);
    expect(pinHashNeedsUpgrade(legacy), isTrue);
  });
}
