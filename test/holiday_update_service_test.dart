import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kouroshyar/features/calendar/holiday_update_service.dart';

void main() {
  group('HolidayUpdateService', () {
    test('accepts a correctly signed Ed25519 holiday feed', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final payload = <String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'revision': 2,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'holidays': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'ilam-1405-04-27',
            'date': '1405-04-27',
            'title': 'تعطیلی ادارات استان',
            'type': 'provincial',
            'scope': 'province',
            'province': 'ایلام',
            'authority': 'استانداری ایلام',
            'sourceUrl': 'https://example.com/notice',
            'publishedAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'active',
          },
        ],
      };
      final payloadBytes = utf8.encode(jsonEncode(payload));
      final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
      final envelope = <String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'payload': base64Encode(payloadBytes),
        'signature': base64Encode(signature.bytes),
      };
      final service = HolidayUpdateService(
        feedUrl: 'https://example.com/holidays.json',
        publicKeyBase64: base64Encode(publicKey.bytes),
      );

      final snapshot = await service.verifyEnvelope(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        currentRevision: 1,
      );

      expect(snapshot.revision, 2);
      expect(snapshot.holidays.single.appliesToProvince('ایلام'), isTrue);
      expect(snapshot.holidays.single.appliesToProvince('تهران'), isFalse);
      expect(snapshot.holidays.single.typeLabel, 'تعطیلی استانی');
    });

    test('does not treat organization-only notices as a province-wide holiday', () {
      final notice = OfficialHolidayUpdate.fromJson(<String, dynamic>{
        'id': 'court-unit-1',
        'date': '1405-04-27',
        'title': 'تعطیلی یک واحد مشخص',
        'type': 'judiciary',
        'scope': 'organization',
        'province': 'ایلام',
        'authority': 'مرجع رسمی آزمایشی',
        'sourceUrl': 'https://example.com/notice',
        'publishedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
      });

      expect(notice.appliesToProvince('ایلام'), isFalse);
    });

    test('rejects a modified signed payload', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final original = utf8.encode(jsonEncode(<String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'revision': 1,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'holidays': const <Object>[],
      }));
      final signature = await algorithm.sign(original, keyPair: keyPair);
      final modified = utf8.encode(jsonEncode(<String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'revision': 2,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'holidays': const <Object>[],
      }));
      final envelope = <String, dynamic>{
        'format': kouroshyarHolidayFeedFormat,
        'payload': base64Encode(modified),
        'signature': base64Encode(signature.bytes),
      };
      final service = HolidayUpdateService(
        feedUrl: 'https://example.com/holidays.json',
        publicKeyBase64: base64Encode(publicKey.bytes),
      );

      await expectLater(
        service.verifyEnvelope(Uint8List.fromList(utf8.encode(jsonEncode(envelope)))),
        throwsA(isA<HolidayUpdateException>()),
      );
    });
  });
  workingHoursFeedTests();
}

void workingHoursFeedTests() {
  group('WorkScheduleUpdateService', () {
    test('derives working_hours.json beside holidays.json', () {
      expect(
        workingHoursFeedUrlFromHolidayFeedUrl('https://example.com/feed/holidays.json'),
        'https://example.com/feed/working_hours.json',
      );
    });

    test('accepts a correctly signed working-hours feed', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final payload = <String, dynamic>{
        'format': kouroshyarWorkScheduleFeedFormat,
        'revision': 3,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'schedules': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'work-ilam-1405-04-27',
            'date': '1405-04-27',
            'title': 'پایان کار ادارات در ساعت ۱۱',
            'scheduleType': 'early_close',
            'scope': 'province',
            'province': 'ایلام',
            'authority': 'استانداری ایلام',
            'sourceUrl': 'https://example.com/notice',
            'publishedAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'active',
            'endTime': '11:00',
            'includedOrganizations': <String>['ادارات'],
          },
        ],
      };
      final payloadBytes = utf8.encode(jsonEncode(payload));
      final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
      final envelope = <String, dynamic>{
        'format': kouroshyarWorkScheduleFeedFormat,
        'payload': base64Encode(payloadBytes),
        'signature': base64Encode(signature.bytes),
      };
      final service = WorkScheduleUpdateService(
        feedUrl: 'https://example.com/working_hours.json',
        publicKeyBase64: base64Encode(publicKey.bytes),
      );

      final snapshot = await service.verifyEnvelope(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        currentRevision: 2,
      );

      expect(snapshot.revision, 3);
      expect(snapshot.schedules.single.appliesToProvince('ایلام'), isTrue);
      expect(snapshot.schedules.single.appliesToProvince('تهران'), isFalse);
      expect(snapshot.schedules.single.typeLabel, 'پایان کار زودتر از موعد');
      expect(snapshot.schedules.single.timeLabel, 'پایان فعالیت در ساعت 11:00');
      expect(snapshot.schedulesForProvinceAndDate('ایلام', '1405-04-27'), hasLength(1));
    });

    test('does not treat working-hours changes as holidays', () {
      final schedule = WorkScheduleUpdate.fromJson(<String, dynamic>{
        'id': 'work-national-1',
        'date': '1405-04-27',
        'title': 'تغییر ساعات کاری ادارات',
        'scheduleType': 'changed_hours',
        'scope': 'national',
        'authority': 'مرجع رسمی آزمایشی',
        'sourceUrl': 'https://example.com/notice',
        'publishedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
        'startTime': '06:00',
        'endTime': '11:00',
      });

      expect(schedule.typeLabel, 'تغییر ساعات کاری');
      expect(schedule.appliesToProvince('هرمزگان'), isTrue);
      expect(schedule.appliesToJalaliDate('1405-04-27'), isTrue);
    });

    test('accepts periodic working hours without treating them as a warning', () {
      final schedule = WorkScheduleUpdate.fromJson(<String, dynamic>{
        'id': 'national-work-hours-1405-summer',
        'date': '1405-02-26',
        'endDate': '1405-06-15',
        'title': 'ساعت کاری ادارات از ۷ تا ۱۳',
        'scheduleType': 'changed_hours',
        'scope': 'national',
        'authority': 'سازمان اداری و استخدامی کشور',
        'sourceUrl': 'https://dolat.ir/detail/481465',
        'publishedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
        'startTime': '07:00',
        'endTime': '13:00',
      });

      expect(schedule.isPeriodicSchedule, isTrue);
      expect(schedule.typeLabel, 'ساعت کاری دوره‌ای');
      expect(schedule.appliesToJalaliDate('1405-04-27'), isTrue);
      expect(schedule.appliesToJalaliDate('1405-06-16'), isFalse);
    });
  });
}
