import 'package:flutter_test/flutter_test.dart';
import 'package:tuition/features/dashboard/admin_dashboard_data.dart';
import 'package:tuition/features/dashboard/admin_dashboard_preferences.dart';

void main() {
  group('consecutiveAbsenceFromRecords', () {
    test('alerts only after three consecutive recorded absences', () {
      final result = consecutiveAbsenceFromRecords(
        mobile: '9999999999',
        records: const [
          AttendanceRecordDay(id: '2026-09-09', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-08', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-07', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-06', data: {'9999999999': true}),
        ],
      );

      expect(result.consecutiveDays, 3);
      expect(result.lastPresentDateKey, '2026-09-06');
    });

    test('stops counting when a present day breaks the chain', () {
      final result = consecutiveAbsenceFromRecords(
        mobile: '9999999999',
        records: const [
          AttendanceRecordDay(id: '2026-09-09', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-08', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-07', data: {'9999999999': true}),
          AttendanceRecordDay(id: '2026-09-06', data: {'9999999999': false}),
        ],
      );

      expect(result.consecutiveDays, 2);
      expect(result.lastPresentDateKey, '2026-09-07');
    });

    test('ignores recorded days that do not include the student', () {
      final result = consecutiveAbsenceFromRecords(
        mobile: '9999999999',
        records: const [
          AttendanceRecordDay(id: '2026-09-09', data: {'8888888888': false}),
          AttendanceRecordDay(id: '2026-09-08', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-07', data: {'9999999999': false}),
          AttendanceRecordDay(id: '2026-09-06', data: {'9999999999': false}),
        ],
      );

      expect(result.consecutiveDays, 3);
      expect(result.lastPresentDateKey, isNull);
    });
  });

  group('AdminDashboardPreferences', () {
    test('uses centralized defaults when Firestore data is missing', () {
      final preferences = AdminDashboardPreferences.fromMap(null);

      expect(preferences.showStudentOverview, isTrue);
      expect(preferences.showAttendanceOverview, isTrue);
      expect(preferences.showPendingFees, isTrue);
      expect(preferences.showConsecutiveAbsenceAlert, isTrue);
      expect(preferences.showTeacherOverview, isTrue);
      expect(preferences.showQrAndAppLink, isTrue);
      expect(preferences.showQuickActions, isTrue);
      expect(preferences.showUpdates, isTrue);
    });

    test('keeps unknown or missing values on defaults', () {
      final preferences = AdminDashboardPreferences.fromMap({
        'showPendingFees': false,
        'showUpdates': 'bad-value',
      });

      expect(preferences.showPendingFees, isFalse);
      expect(preferences.showUpdates, isTrue);
    });
  });
}
