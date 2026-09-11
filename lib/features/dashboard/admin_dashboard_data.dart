import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/constants/academic_catalog.dart';

class AdminDashboardDataService {
  AdminDashboardDataService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<AdminDashboardSummary> loadSummary() async {
    Object? peopleError;
    Object? pendingSignupError;
    Object? attendanceError;
    Object? pendingFeesError;
    Object? absenceError;
    List<AdminUserRecord> users = const [];

    try {
      final usersSnap = await _firestore.collection('users').get();
      users = usersSnap.docs
          .map((doc) => AdminUserRecord.fromDoc(doc.id, doc.data()))
          .toList();
    } catch (error, stackTrace) {
      peopleError = error;
      debugPrint('Admin dashboard users summary failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    final activeStudents = users
        .where((user) => user.role == 'student' && user.active)
        .toList();
    final activeTeachers = users
        .where((user) => user.role == 'teacher' && user.active)
        .toList();
    var pendingSignupCount = 0;
    try {
      final pendingSnap = await _firestore
          .collection('pending_users')
          .where('role', isEqualTo: 'student')
          .get();
      pendingSignupCount = pendingSnap.docs.length;
    } catch (error, stackTrace) {
      pendingSignupError = error;
      debugPrint('Admin dashboard pending signups failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    var todayAttendance = AttendanceTodaySummary.empty;
    try {
      todayAttendance = await _loadTodayAttendance();
    } catch (error, stackTrace) {
      attendanceError = error;
      debugPrint('Admin dashboard attendance summary failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    var pendingFees = PendingFeesSummary.empty;
    try {
      pendingFees = await _loadPendingFees();
    } catch (error, stackTrace) {
      pendingFeesError = error;
      debugPrint('Admin dashboard pending fees failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    var absenceAlerts = const <ConsecutiveAbsenceAlert>[];
    try {
      absenceAlerts = await _loadConsecutiveAbsenceAlerts(activeStudents);
    } catch (error, stackTrace) {
      absenceError = error;
      debugPrint('Admin dashboard consecutive absence failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    return AdminDashboardSummary(
      totalStudents: users.where((user) => user.role == 'student').length,
      activeStudents: activeStudents.length,
      teacherCount: activeTeachers.length,
      pendingSignupCount: pendingSignupCount,
      todayAttendance: todayAttendance,
      pendingFees: pendingFees,
      absenceAlerts: absenceAlerts,
      peopleError: peopleError,
      pendingSignupError: pendingSignupError,
      attendanceError: attendanceError,
      pendingFeesError: pendingFeesError,
      absenceError: absenceError,
    );
  }

  Future<AttendanceTodaySummary> _loadTodayAttendance() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var totalMarked = 0;
    var present = 0;
    var absent = 0;

    for (final className in AcademicCatalog.classValues) {
      for (final batch in AcademicCatalog.batchValues) {
        final doc = await _firestore
            .collection('attendance')
            .doc(AcademicCatalog.batchDocId(className, batch))
            .collection('records')
            .doc(dateKey)
            .get();
        final data = doc.data();
        if (data == null) continue;
        for (final value in data.values) {
          if (value is! bool) continue;
          totalMarked++;
          if (value) {
            present++;
          } else {
            absent++;
          }
        }
      }
    }

    return AttendanceTodaySummary(
      totalMarked: totalMarked,
      present: present,
      absent: absent,
    );
  }

  Future<PendingFeesSummary> _loadPendingFees() async {
    final usersSnap = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();
    final activeStudents = usersSnap.docs
        .where((doc) => doc.data()['active'] != false)
        .map((doc) => AdminUserRecord.fromDoc(doc.id, doc.data()))
        .toList();

    final feeDocs = await Future.wait(
      AcademicCatalog.classValues.map(
        (className) =>
            _firestore.collection('fees').doc('Class-$className').get(),
      ),
    );
    final feesByClass = {
      for (final doc in feeDocs) doc.id.replaceFirst('Class-', ''): doc.data(),
    };

    var pendingStudents = 0;
    var outstandingAmount = 0.0;
    for (final student in activeStudents) {
      final classFees = feesByClass[student.className];
      if (classFees == null) continue;
      final expected = _expectedMonthlyFee(classFees);
      if (expected <= 0) continue;

      final rawStudents = classFees['students'];
      final studentFeeData = rawStudents is Map<String, dynamic>
          ? rawStudents[student.mobile]
          : null;
      final payments = studentFeeData is Map<String, dynamic>
          ? List<dynamic>.from(studentFeeData['payments'] ?? [])
          : const <dynamic>[];
      final paidThisMonth = paidInCurrentMonth(payments);
      if (paidThisMonth >= expected) continue;

      pendingStudents++;
      outstandingAmount += expected - paidThisMonth;
    }

    return PendingFeesSummary(
      pendingStudents: pendingStudents,
      outstandingAmount: outstandingAmount,
    );
  }

  Future<List<ConsecutiveAbsenceAlert>> _loadConsecutiveAbsenceAlerts(
    List<AdminUserRecord> activeStudents,
  ) async {
    final studentsByAttendanceDoc = <String, List<AdminUserRecord>>{};
    for (final student in activeStudents) {
      if (student.className.isEmpty) continue;
      final docId = AcademicCatalog.batchDocId(
        student.className,
        student.batch,
      );
      studentsByAttendanceDoc.putIfAbsent(docId, () => []).add(student);
    }

    final alerts = <ConsecutiveAbsenceAlert>[];
    final dateKeys = _recentDateKeys(maxCalendarDays: 45);
    for (final entry in studentsByAttendanceDoc.entries) {
      final recordsCollection = _firestore
          .collection('attendance')
          .doc(entry.key)
          .collection('records');
      final recordDocs = await Future.wait(
        dateKeys.map((dateKey) => recordsCollection.doc(dateKey).get()),
      );

      final records = <AttendanceRecordDay>[];
      for (final doc in recordDocs) {
        final data = doc.data();
        if (!doc.exists || data == null) continue;
        records.add(AttendanceRecordDay(id: doc.id, data: data));
      }
      for (final student in entry.value) {
        final result = consecutiveAbsenceFromRecords(
          records: records,
          mobile: student.mobile,
        );
        if (result.consecutiveDays < 3) continue;
        alerts.add(
          ConsecutiveAbsenceAlert(
            student: student,
            consecutiveDays: result.consecutiveDays,
            lastPresentDateKey: result.lastPresentDateKey,
          ),
        );
      }
    }

    alerts.sort((a, b) {
      final countCompare = b.consecutiveDays.compareTo(a.consecutiveDays);
      if (countCompare != 0) return countCompare;
      return a.student.name.toLowerCase().compareTo(
        b.student.name.toLowerCase(),
      );
    });
    return alerts;
  }

  List<String> _recentDateKeys({required int maxCalendarDays}) {
    final formatter = DateFormat('yyyy-MM-dd');
    final today = DateTime.now();
    return List.generate(maxCalendarDays, (index) {
      return formatter.format(today.subtract(Duration(days: index)));
    });
  }
}

double paidInCurrentMonth(List<dynamic> payments, {DateTime? now}) {
  final current = now ?? DateTime.now();
  return payments.fold<double>(0, (total, payment) {
    if (payment is! Map<String, dynamic>) return total;
    final rawDate = payment['date'];
    final date = rawDate is Timestamp ? rawDate.toDate() : null;
    if (date == null ||
        date.month != current.month ||
        date.year != current.year) {
      return total;
    }
    final amount = payment['amount'];
    return total + (amount is num ? amount.toDouble() : 0);
  });
}

double _expectedMonthlyFee(Map<String, dynamic> feeData) {
  final mode = feeData['mode']?.toString();
  final value = mode == 'annual'
      ? feeData['installment']
      : feeData['monthlyFee'];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

ConsecutiveAbsenceResult consecutiveAbsenceFromRecords({
  required List<AttendanceRecordDay> records,
  required String mobile,
}) {
  var consecutiveDays = 0;
  String? lastPresentDateKey;

  for (final record in records) {
    final value = record.data[mobile];
    if (value is! bool) continue;
    if (value) {
      lastPresentDateKey = record.id;
      break;
    }
    consecutiveDays++;
  }

  return ConsecutiveAbsenceResult(
    consecutiveDays: consecutiveDays,
    lastPresentDateKey: lastPresentDateKey,
  );
}

class AdminDashboardSummary {
  const AdminDashboardSummary({
    required this.totalStudents,
    required this.activeStudents,
    required this.teacherCount,
    required this.pendingSignupCount,
    required this.todayAttendance,
    required this.pendingFees,
    required this.absenceAlerts,
    required this.peopleError,
    required this.pendingSignupError,
    required this.attendanceError,
    required this.pendingFeesError,
    required this.absenceError,
  });

  final int totalStudents;
  final int activeStudents;
  final int teacherCount;
  final int pendingSignupCount;
  final AttendanceTodaySummary todayAttendance;
  final PendingFeesSummary pendingFees;
  final List<ConsecutiveAbsenceAlert> absenceAlerts;
  final Object? peopleError;
  final Object? pendingSignupError;
  final Object? attendanceError;
  final Object? pendingFeesError;
  final Object? absenceError;
}

class AttendanceTodaySummary {
  const AttendanceTodaySummary({
    required this.totalMarked,
    required this.present,
    required this.absent,
  });

  final int totalMarked;
  final int present;
  final int absent;

  static const empty = AttendanceTodaySummary(
    totalMarked: 0,
    present: 0,
    absent: 0,
  );
}

class PendingFeesSummary {
  const PendingFeesSummary({
    required this.pendingStudents,
    required this.outstandingAmount,
  });

  final int pendingStudents;
  final double outstandingAmount;

  static const empty = PendingFeesSummary(
    pendingStudents: 0,
    outstandingAmount: 0,
  );
}

class ConsecutiveAbsenceAlert {
  const ConsecutiveAbsenceAlert({
    required this.student,
    required this.consecutiveDays,
    required this.lastPresentDateKey,
  });

  final AdminUserRecord student;
  final int consecutiveDays;
  final String? lastPresentDateKey;
}

class ConsecutiveAbsenceResult {
  const ConsecutiveAbsenceResult({
    required this.consecutiveDays,
    required this.lastPresentDateKey,
  });

  final int consecutiveDays;
  final String? lastPresentDateKey;
}

class AttendanceRecordDay {
  const AttendanceRecordDay({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class AdminUserRecord {
  const AdminUserRecord({
    required this.mobile,
    required this.name,
    required this.role,
    required this.className,
    required this.batch,
    required this.active,
    required this.guardianContact,
  });

  factory AdminUserRecord.fromDoc(String id, Map<String, dynamic> data) {
    final mobile = data['mobile']?.toString().trim();
    final name = data['name']?.toString().trim();
    return AdminUserRecord(
      mobile: mobile == null || mobile.isEmpty ? id : mobile,
      name: name == null || name.isEmpty ? 'Unnamed' : name,
      role: data['role']?.toString().trim() ?? '',
      className: data['class']?.toString().trim() ?? '',
      batch: AcademicCatalog.normalizeBatch(data['batch']?.toString()),
      active: data['active'] != false,
      guardianContact:
          data['guardianMobile']?.toString().trim().isNotEmpty == true
          ? data['guardianMobile'].toString().trim()
          : data['parentMobile']?.toString().trim().isNotEmpty == true
          ? data['parentMobile'].toString().trim()
          : data['mobile']?.toString().trim() ?? id,
    );
  }

  final String mobile;
  final String name;
  final String role;
  final String className;
  final String batch;
  final bool active;
  final String guardianContact;
}
