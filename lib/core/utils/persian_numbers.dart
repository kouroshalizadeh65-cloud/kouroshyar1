String toPersianDigits(Object? value) {
  final input = value?.toString() ?? '';
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  var output = input;
  for (var i = 0; i < en.length; i++) {
    output = output.replaceAll(en[i], fa[i]);
  }
  return output;
}
