import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/database/app_database.dart';

void main() {
  test('شناسه شخص در تراکنش ذخیره و بازیابی می‌شود', () {
    final transaction = PersonalAccountTransaction.fromJson({
      'id': 10,
      'personId': 7,
      'personName': 'علی رضایی',
      'type': 'پرداختی من',
      'amount': 100000,
      'date': '2026-07-11T00:00:00.000',
      'createdAt': '2026-07-11T00:00:00.000',
    });

    expect(transaction.personId, 7);
    expect(transaction.toJson()['personId'], 7);
  });
}
