import 'package:flutter/services.dart';

import 'persian_numbers.dart';

String normalizeMoneyDigits(String input) {
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var output = input;
  for (var i = 0; i < 10; i++) {
    output = output.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return output;
}

String _addThousandsDots(String digits) {
  final clean = digits.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < clean.length; i++) {
    final remaining = clean.length - i;
    buffer.write(clean[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}

String formatMoneyInput(String input) => _addThousandsDots(normalizeMoneyDigits(input));

double? parseMoney(String input) {
  final clean = normalizeMoneyDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) return null;
  return double.tryParse(clean);
}

String formatMoney(num value, {bool persianDigits = true}) {
  final formatted = _addThousandsDots(value.round().toString());
  return persianDigits ? toPersianDigits(formatted) : formatted;
}

class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = formatMoneyInput(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
