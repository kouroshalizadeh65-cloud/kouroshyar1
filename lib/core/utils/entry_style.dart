import 'package:flutter/material.dart';

IconData entryIcon(String? type) {
  switch (type) {
    case 'جلسه':
      return Icons.event;
    case 'مالی':
      return Icons.payments;
    case 'حقوقی':
      return Icons.gavel;
    case 'تماس':
      return Icons.call;
    case 'مهلت':
      return Icons.warning_amber;
    default:
      return Icons.notes;
  }
}

Color entryColor(String? type) {
  switch (type) {
    case 'جلسه':
      return Colors.blue;
    case 'مالی':
      return Colors.green;
    case 'حقوقی':
      return Colors.deepPurple;
    case 'تماس':
      return Colors.orange;
    case 'مهلت':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
