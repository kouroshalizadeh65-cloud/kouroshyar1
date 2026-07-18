import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/date_format_fa.dart';
import '../utils/persian_numbers.dart';

int _jalaliMonthLength(int year, int month) {
  final start = jalaliToGregorian(year, month, 1);
  final next = month == 12 ? jalaliToGregorian(year + 1, 1, 1) : jalaliToGregorian(year, month + 1, 1);
  return next.difference(start).inDays;
}

const List<String> _monthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

Future<DateTime?> pickPersianDate(
  BuildContext context, {
  required DateTime initialDate,
  String title = 'انتخاب تاریخ',
}) async {
  final initialJalali = gregorianToJalali(initialDate);
  var year = initialJalali.year;
  var month = initialJalali.month;
  var day = initialJalali.day;

  DateTime compose() {
    final maxDay = _jalaliMonthLength(year, month);
    if (day > maxDay) day = maxDay;
    final gregorian = jalaliToGregorian(year, month, day);
    return DateTime(
      gregorian.year,
      gregorian.month,
      gregorian.day,
      initialDate.hour,
      initialDate.minute,
    );
  }

  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (sheetContext, setState) {
          final media = MediaQuery.of(sheetContext);
          final bottomSafe = math.max(media.padding.bottom, 16.0);
          final bottomInset = media.viewInsets.bottom;
          final days = List<int>.generate(_jalaliMonthLength(year, month), (index) => index + 1);
          final years = List<int>.generate(31, (index) => initialJalali.year - 10 + index);
          if (!years.contains(year)) years.add(year);
          years.sort();

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSafe + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      formatPersianLongDate(compose()),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: DropdownButtonFormField<int>(
                                value: year,
                                decoration: const InputDecoration(labelText: 'سال'),
                                items: years
                                    .map((value) => DropdownMenuItem(value: value, child: Text(toPersianDigits(value.toString()))))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => year = value);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: DropdownButtonFormField<int>(
                                value: month,
                                decoration: const InputDecoration(labelText: 'ماه'),
                                items: List<int>.generate(12, (index) => index + 1)
                                    .map((value) => DropdownMenuItem(value: value, child: Text(_monthNames[value - 1])))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => month = value);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: DropdownButtonFormField<int>(
                                value: days.contains(day) ? day : days.last,
                                decoration: const InputDecoration(labelText: 'روز'),
                                items: days
                                    .map((value) => DropdownMenuItem(value: value, child: Text(toPersianDigits(value.toString()))))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => day = value);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('امروز'),
                          onPressed: () {
                            final j = gregorianToJalali(DateTime.now());
                            setState(() {
                              year = j.year;
                              month = j.month;
                              day = j.day;
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('فردا'),
                          onPressed: () {
                            final j = gregorianToJalali(DateTime.now().add(const Duration(days: 1)));
                            setState(() {
                              year = j.year;
                              month = j.month;
                              day = j.day;
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('پس‌فردا'),
                          onPressed: () {
                            final j = gregorianToJalali(DateTime.now().add(const Duration(days: 2)));
                            setState(() {
                              year = j.year;
                              month = j.month;
                              day = j.day;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('لغو'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, compose()),
                            child: const Text('انتخاب تاریخ'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
